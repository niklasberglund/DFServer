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

#import "DFPassiveServer.h"
#import "DFServer.h"

@implementation DFPassiveServer


- (id)initForPort:(int)listenPort returnData:(NSData *)data completionBlock:(void(^)())completionBlock
{
    self = [super init];
    
    if (self) {
        self.host = [DFServer deviceIPAddress];
        self.port = listenPort;
        self.returnData = data;
        self.completionBlock  = completionBlock;
        
        dispatch_queue_t passiveServerQueue = dispatch_queue_create("passive_server", nil);
        
        self->listenSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:nil];
        [self startListening];
    }
    
    return self;
}


- (id)initForPort:(int)listenPort
{
    self = [super init];
    
    if (self) {
        self.host = [DFServer deviceIPAddress];
        self.port = listenPort;
        
        self->listenSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:nil];
        [self startListening];
    }
    
    return self;
}


- (BOOL)startListening
{
    NSError *startListeningError;
    [self->listenSocket acceptOnPort:self.port error:&startListeningError];
    
    if (startListeningError) {
        NSLog(@"Error: %@", startListeningError);
        return NO;
    }
    else {
        return YES;
    }
}


+ (DFPassiveServer *)spawnPassiveServerForReturnData:(NSData *)returnData withCompletionBlock:(void(^)())completionBlock
{
    static int port = 4200; // start here and keep incrementing
    
    DFPassiveServer *passiveServer = [[DFPassiveServer alloc] initForPort:port returnData:returnData completionBlock:completionBlock];
    
    port++;
    
    return passiveServer;
}


+ (DFPassiveServer *)spawnPassiveServer
{
    static int port = 4200; // start here and keep incrementing
    
    DFPassiveServer *passiveServer = [[DFPassiveServer alloc] initForPort:port];
    
    port++;
    
    return passiveServer;
}


- (NSString *)hostPortRepresentation
{
    int p2 = self.port % 256;
    int p1 = (self.port - p2) / 256;
    
    NSArray *hostSeparated = [self.host componentsSeparatedByString:@"."];
    int h1 = (int)[[hostSeparated objectAtIndex:0] integerValue];
    int h2 = (int)[[hostSeparated objectAtIndex:1] integerValue];
    int h3 = (int)[[hostSeparated objectAtIndex:2] integerValue];
    int h4 = (int)[[hostSeparated objectAtIndex:3] integerValue];
    
    return [NSString stringWithFormat:@"%i,%i,%i,%i,%i,%i", h1, h2, h3, h4, p1, p2];
}


- (void)writeData:(NSData *)data completionBlock:(void (^)())completionBlock
{

}


#pragma mark - GCDAsyncSocketDelegate methods

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    self->clientSocket = newSocket;
    
    [newSocket writeData:self.returnData withTimeout:60.0 tag:0];
}


- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    if (self.completionBlock) {
        self.completionBlock();
    }
    else {
        NSLog(@"ERROR: No completion block");
    }
}


@end
