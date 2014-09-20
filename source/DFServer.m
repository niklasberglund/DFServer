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

static const int REQUESTED_ACTION_COMPLETED = 200;
static const int SYSTEM_TYPE = 215;
static const int ENTERING_PASSIVE_MODE = 227;
static const int USER_LOGGED_IN = 230;

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


- (void)writeMessage:(NSString *)message withCode:(int)code toSocket:(GCDAsyncSocket *)socket
{
    NSString *messageString = [NSString stringWithFormat:@"%i %@", code, message];
    
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


#pragma mark - delegate callbacks

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

- (void)handleUSERCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    [self writeMessage:@"Logged in" withCode:USER_LOGGED_IN toSocket:socket];
}


- (void)handleTYPECommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    [self writeMessage:@"Pretending to care about TYPE" withCode:REQUESTED_ACTION_COMPLETED toSocket:socket];
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


- (void)handlePASVCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    [self writeMessage:@"Entering Passive Mode (192,168,150,90,195,149)." withCode:ENTERING_PASSIVE_MODE toSocket:socket];
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
    NSMutableDictionary *userDataDict = (NSMutableDictionary *)socket.userData;
    [userDataDict setValue:portSocket forKey:@"port_socket"];
    
    NSLog(@"%@", userDataDict);
    
    [self writeMessage:@"PORT command is successful" withCode:200 toSocket:socket];
}


- (void)handleLISTCommandWithArguments:(NSArray *)arguments forSocket:(GCDAsyncSocket *)socket
{
    NSLog(@"LIST");
    NSString *stringListing = [self->fileSystemNavigator listForPath:@"/" error:nil];
    NSLog(@"%@", stringListing);
    //[self writeMessage:@"Data connection accepted " withCode:150 toSocket:socket];
    
    //[self writeRawMessage:<#(NSString *)#> toSocket:<#(GCDAsyncSocket *)#>]
    //[self writeRawMessage:stringListing toSocket:socket];
    //[self writeMessage:@"Listing completed." withCode:226 toSocket:socket];
    
    [self writeMessage:@"Data connection accepted " withCode:150 toSocket:socket];
    
    NSData *returnData = [stringListing dataUsingEncoding:NSUTF8StringEncoding];
    
    [DFPassiveServer spawnPassiveServerForReturnData:returnData withCompletionBlock:^{
        NSLog(@"passive server sent data");
        [self writeMessage:@"Listing completed." withCode:226 toSocket:socket];
    }];
    
    NSMutableDictionary *userDataDict = (NSMutableDictionary *)socket.userData;
    GCDAsyncSocket *dataSocket = [userDataDict valueForKey:@"port_socket"];
    
    [self writeRawMessage:@"150 Data connection accepted from ip5.ip6.ip7.ip8:4279; transfer starting.\n         -rw-r—r— 1 ixl users 16 May 22 17:47 testfile.txt\n         226 Listing completed." toSocket:dataSocket];
    [dataSocket disconnectAfterWriting];
}


- (void)socket:(GCDAsyncSocket *)sock didReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag
{
    NSLog(@"read partial data");
}


- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    NSLog(@"Wrote data");
}


+ (NSString *)deviceIPAddress
{
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    
    #if TARGET_IPHONE_SIMULATOR
        // You might wanna change this line below depending on which network interface you use
        NSString *networkInterface = @"en0";
    #else
        NSString *networkInterface = @"en0";
    #endif
    
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
