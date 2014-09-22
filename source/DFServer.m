//
//  The MIT License (MIT)
//
//  Copyright (c) 2014 Niklas Berglund
//
//      Permission is hereby granted, free of charge, to any person obtaining a copy
//      of this software and associated documentation files (the "Software"), to deal
//      in the Software without restriction, including without limitation the rights
//      to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//      copies of the Software, and to permit persons to whom the Software is
//      furnished to do so, subject to the following conditions:
//
//      The above copyright notice and this permission notice shall be included in
//      all copies or substantial portions of the Software.
//
//      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//      IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//      FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//      AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//      LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//      OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//      THE SOFTWARE.
//

#import "DFServer.h"
#include "TargetConditionals.h"
#include <ifaddrs.h>
#include <arpa/inet.h>

@implementation DFServer

static const int TRANSFER_MODE_ASCII = 0;
static const int TRANSFER_MODE_BINARY = 1;

static const int REQUESTED_ACTION_COMPLETED = 200;
static const int FILE_STATUS = 213;
static const int SYSTEM_TYPE = 215;
static const int CLOSING_CONTROL_CONNECTION = 221;
static const int ENTERING_PASSIVE_MODE = 227;
static const int USER_LOGGED_IN = 230;
static const int REQUESTED_FILE_ACTION_OK = 250;
static const int REQUESTED_ACTION_NOT_TAKEN_FILE_UNAVAILABLE = 550;

+ (NSData *)LFData
{
    return [NSData dataWithBytes:"\x0A" length:1];
}

+ (NSData *)CRData
{
    return [NSData dataWithBytes:"\x0D" length:1];
}

+ (NSData *)LFCRData
{
    return [NSData dataWithBytes:"\x0A\x0D" length:2];
}

+ (NSData *)CRLFData
{
    return [NSData dataWithBytes:"\x0D\x0A" length:2];
}

+ (NSData *)NULLData
{
    return [NSData dataWithBytes:"\x00" length:1];
}


- (id)init
{
    self = [super init];
    
    if (self) {
        self->sockets = [[NSMutableArray alloc] init];
        self->socketQueue = dispatch_queue_create("debug_ftp_server_socket_queue", nil);
        self->listenSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:socketQueue];
        self->fileSystemNavigator = [[DFFilesystemNavigator alloc] init];
    }
    
    return self;
}

- (BOOL)startListening
{
    return [self startListeningOnPort:21];
}


- (BOOL)startListeningOnPort:(int)port
{
    NSError *startListenError;
    BOOL startSuccess = [listenSocket acceptOnPort:port error:&startListenError];
    
    if (!startSuccess) {
        NSLog(@"ERROR: Failed to start listening on port %i", port);
        NSLog(@"%@", startListenError);
        return NO;
    }
    
    NSLog(@"Started listening on port %i", port);
    
    return YES;
}


- (void)stop
{
    [self->listenSocket disconnect];
}


- (void)stopPassiveServer
{
    [self->passiveServer disconnect];
    self->passiveServer = nil;
}


#pragma mark - write methods


- (void)writeMessage:(NSString *)message withCode:(int)code toSocket:(GCDAsyncSocket *)socket
{
    NSString *messageString = [NSString stringWithFormat:@"%i %@", code, message];
    
    NSMutableData *messageData = [[messageString dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [messageData appendData:[NSData dataWithBytes:"\x0D\x0A" length:2]];
    
    [socket writeData:messageData withTimeout:60.0 tag:0];
}


- (void)writeMessage:(NSString *)message withCode:(int)code begin:(BOOL)begin toSocket:(GCDAsyncSocket *)socket
{
    NSString *messageString;
    
    if (begin) {
        messageString= [NSString stringWithFormat:@"%i- %@", code, message];
    }
    else {
        messageString= [NSString stringWithFormat:@"%i %@", code, message];
    }
    
    NSMutableData *messageData = [[messageString dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [messageData appendData:[NSData dataWithBytes:"\x0D\x0A" length:2]];
    
    [socket writeData:messageData withTimeout:60.0 tag:0];
}


- (void)writeRawMessage:(NSString *)message toSocket:(GCDAsyncSocket *)socket
{
    NSMutableData *messageData = [[message dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [messageData appendData:[NSData dataWithBytes:"\x0D\x0A" length:2]];
    [socket writeData:messageData withTimeout:60.0 tag:0];
}


#pragma mark - handle FTP commands

- (void)handleUSERCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    [self writeMessage:@"Logged in" withCode:USER_LOGGED_IN toSocket:socket];
}


- (void)handleTYPECommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    NSString *modeIdentifier = [arguments objectAtIndex:0];
    NSString *modeName;
    
    if ([modeIdentifier isEqualToString:@"A"]) {
        self->transferMode = TRANSFER_MODE_ASCII;
        modeName = @"ASCII";
    }
    else if ([modeIdentifier isEqualToString:@"I"]) {
        self->transferMode = TRANSFER_MODE_BINARY;
        modeName = @"BINARY";
    }
    else {
        NSLog(@"Error: unknown TYPE identfier");
    }
    
    [self writeMessage:[NSString stringWithFormat:@"Set type %@", modeName] withCode:REQUESTED_ACTION_COMPLETED toSocket:socket];
}


- (void)handleSYSTCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    [self writeMessage:@"IOS" withCode:SYSTEM_TYPE toSocket:socket];
}


- (void)handleFEATCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    [self writeMessage:@"end" withCode:211 toSocket:socket]; // not listing any features
}


- (void)handlePWDCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    NSString *currentPath = [self->fileSystemNavigator pwd];
    [self writeMessage:currentPath withCode:257 toSocket:socket];
}


- (void)handleCWDCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    NSString *directoryName = arguments[0]; // no support for spaces at the moment. TODO
    
    BOOL success = [self->fileSystemNavigator changeWorkingDirectory:directoryName];
    
    if (success) {
        [self writeMessage:@"CWD command successful. " withCode:REQUESTED_ACTION_COMPLETED toSocket:socket];
    }
    else {
        [self writeMessage:@"Failed to change directory." withCode:REQUESTED_ACTION_NOT_TAKEN_FILE_UNAVAILABLE toSocket:socket];
    }
}


- (void)handlePASVCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    self->passiveServer = [DFPassiveServer spawnPassiveServer];
    NSString *hostPortRepresentation = [self->passiveServer hostPortRepresentation];
    
    NSString *responseString = [NSString stringWithFormat:@"=%@", hostPortRepresentation];
    NSLog(@"PASV response: %@", responseString);
    [self writeMessage:responseString withCode:ENTERING_PASSIVE_MODE toSocket:socket];
}


- (void)handlePORTCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    NSString *value = [arguments objectAtIndex:0];
    NSArray *portSeparated = [value componentsSeparatedByString:@","];
    NSString *portHost = [
                          NSString stringWithFormat:@"%@.%@.%@.%@",
                          [portSeparated objectAtIndex:0],
                          [portSeparated objectAtIndex:1],
                          [portSeparated objectAtIndex:2],
                          [portSeparated objectAtIndex:3]
                          ];
    int portPort = (int)[[portSeparated objectAtIndex:4] integerValue] * 256 + (int)[[portSeparated objectAtIndex:5] integerValue];
    NSLog(@"%@", value);
    NSLog(@"%@", portHost);
    NSLog(@"%i", portPort);
    
    if ([socket userData] == nil) {
        socket.userData = [[NSMutableDictionary alloc] init];
    }
    
    GCDAsyncSocket *portSocket = [[GCDAsyncSocket alloc] init];
    [portSocket connectToHost:portHost onPort:portPort error:nil];
    //NSMutableDictionary *userDataDict = (NSMutableDictionary *)socket.userData;
    //[userDataDict setValue:portSocket forKey:@"port_socket"];
    
    //NSLog(@"%@", userDataDict);
    
    [self writeMessage:@"PORT command is successful" withCode:200 toSocket:socket]; // currently not supported. TODO
}


- (void)handleLISTCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    NSLog(@"LIST");
    NSString *stringListing = [self->fileSystemNavigator listForPath:@"/" error:nil];
    NSLog(@"%@", stringListing);
    
    [self writeMessage:@"Data connection accepted " withCode:150 toSocket:socket];
    
    NSData *returnData = [stringListing dataUsingEncoding:NSUTF8StringEncoding];
    [self->passiveServer setReturnData:returnData];
    [self->passiveServer writeData];
    
    __weak typeof(self) weakSelf = self;
    [self->passiveServer setCompletionBlock:^{
        NSLog(@"passive server sent data");
        [weakSelf writeMessage:@"Listing completed." withCode:226 toSocket:socket];
        
        [weakSelf stopPassiveServer];
    }];
    
    //NSMutableDictionary *userDataDict = (NSMutableDictionary *)socket.userData;
    //GCDAsyncSocket *dataSocket = [userDataDict valueForKey:@"port_socket"];
}


- (void)handleMLSTCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    NSString *target = [arguments componentsJoinedByString:@" "];
    NSString *targetFullPath = [NSString stringWithFormat:@"%@/%@", [self->fileSystemNavigator currentPath], target];
    NSString *targetVirtualPath = [NSString stringWithFormat:@"%@/%@", [self->fileSystemNavigator currentVirtualPath], target];
    
    NSError *readAttributesError;
    NSDictionary *targetInfoDict = [[NSFileManager defaultManager] attributesOfItemAtPath:targetFullPath error:&readAttributesError];
    
    if (readAttributesError) {
        [self writeMessage:@"Seems like the file could not be found." withCode:REQUESTED_ACTION_NOT_TAKEN_FILE_UNAVAILABLE toSocket:socket];
        return;
    }
    
    long long fileSize = [[targetInfoDict valueForKey:@"NSFileSize"] longLongValue];
    NSString *fileType = [targetInfoDict valueForKey:@"NSFileType"];
    NSString *fileTypeString = @"file";
    if ([fileType isEqualToString:NSFileTypeDirectory]) {
        fileTypeString = @"dir";
    }
    
    
    NSString *beginMessage = [NSString stringWithFormat:@"Listing %@", target];
    NSString *responseString = [NSString stringWithFormat:@" type=%@;perm=r;size=%lld; %@", fileTypeString, fileSize, targetVirtualPath];
    
    NSLog(@"%@", beginMessage);
    NSLog(@"%@", responseString);
    
    [self writeMessage:beginMessage withCode:250 begin:YES toSocket:socket];
    [self writeRawMessage:responseString toSocket:socket];
    [self writeMessage:@"End" withCode:250 toSocket:socket];
}

- (void)handleSIZECommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    NSString *target = [arguments componentsJoinedByString:@" "];
    NSString *targetFullPath = [NSString stringWithFormat:@"%@/%@", [self->fileSystemNavigator currentPath], target];
    NSError *readAttributesError;
    NSDictionary *targetInfoDict = [[NSFileManager defaultManager] attributesOfItemAtPath:targetFullPath error:&readAttributesError];
    
    if (readAttributesError) {
        [self writeMessage:@"Seems like the file could not be found." withCode:REQUESTED_ACTION_NOT_TAKEN_FILE_UNAVAILABLE toSocket:socket];
        return;
    }
    
    long long fileSize = [[targetInfoDict valueForKey:@"NSFileSize"] longLongValue];
    
    [self writeMessage:[NSString stringWithFormat:@"%lld", fileSize] withCode:FILE_STATUS toSocket:socket];
}

/**
 * Modification time. http://tools.ietf.org/html/rfc3659#section-3.3
 */
- (void)handleMDTMCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    NSString *target = [arguments componentsJoinedByString:@" "];
    NSString *targetFullPath = [NSString stringWithFormat:@"%@/%@", [self->fileSystemNavigator currentPath], target];
    NSError *readAttributesError;
    NSDictionary *targetInfoDict = [[NSFileManager defaultManager] attributesOfItemAtPath:targetFullPath error:&readAttributesError];
    
    if (readAttributesError) {
        [self writeMessage:@"Seems like the file could not be found." withCode:REQUESTED_ACTION_NOT_TAKEN_FILE_UNAVAILABLE toSocket:socket];
        return;
    }
    
    NSDate *modificationDate = [targetInfoDict valueForKey:@"NSFileModificationDate"];
    NSDateFormatter *responseDateFormatter = [[NSDateFormatter alloc] init];
    [responseDateFormatter setDateFormat:@"yyyyMMddHHmm"];
    
    [self writeMessage:[responseDateFormatter stringFromDate:modificationDate] withCode:FILE_STATUS toSocket:socket];
}


- (void)handleEXITCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    [self writeMessage:@"Goodbye" withCode:CLOSING_CONTROL_CONNECTION toSocket:socket];
    [socket disconnectAfterWriting];
}


#pragma mark - GCDAsyncSocket delegate methods


- (void)socket:(GCDAsyncSocket *)sock didReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag
{
    NSLog(@"read partial data");
}


- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    NSLog(@"Wrote data");
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    NSLog(@"Accepted socket %@", newSocket);
    [self->sockets addObject:newSocket];
    
    NSString *responseString = @"200 Welcome to this _debug_ server\n";
    [newSocket writeData:[responseString dataUsingEncoding:NSUTF8StringEncoding] withTimeout:60.0 tag:0];
    [newSocket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:60.0 tag:0];
}


- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    [self->sockets removeObject:sock];
}


- (void)socket:(GCDAsyncSocket *)socket didReadData:(NSData *)data withTag:(long)tag
{
    NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSString *lastCharacter = [dataString substringFromIndex:dataString.length-1];
    
    if ([lastCharacter isEqualToString:@"\n"] || [lastCharacter isEqualToString:@"\r"]) {
        dataString = [dataString substringToIndex:dataString.length - 2];
    }
    
    NSArray *components = [dataString componentsSeparatedByString:@" "];
    NSString *command = [components firstObject];
    NSArray *arguments;
    
    if (components.count > 1) {
        arguments = [components subarrayWithRange:NSMakeRange(1, components.count - 1)];
    }
    else {
        arguments = nil;
    }
    
    NSLog(@"%@", dataString);
    NSLog(@"%@", command);
    
    SEL handleCommandMethod = NSSelectorFromString([NSString stringWithFormat:@"handle%@CommandWithArguments:forSocket:", command]);
    
    if ([self respondsToSelector:handleCommandMethod]) {
        [self performSelector:handleCommandMethod withObject:arguments withObject:socket];
    }
    else {
        NSLog(@"Warning: unrecognized command '%@'", command);
    }
    
    [socket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:60.0 tag:0];
}


#pragma mark - helpers


+ (NSString *)deviceIPAddress
{
    #if TARGET_IPHONE_SIMULATOR
        return @"127.0.0.1";
    #endif
    
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    NSString *networkInterface = @"en0";
    
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if( temp_addr->ifa_addr->sa_family == AF_INET) {
                // Check if interface is en0 which is the wifi connection on the iPhone
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:networkInterface]) {
                    // Get NSString from C String
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            
            temp_addr = temp_addr->ifa_next;
        }
    }
    
    // Free memory
    freeifaddrs(interfaces);
    
    return address;
}


@end
