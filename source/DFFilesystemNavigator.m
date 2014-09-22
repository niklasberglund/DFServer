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

#import "DFFilesystemNavigator.h"

@implementation DFFilesystemNavigator

- (id)init
{
    self = [super init];
    
    if (self) {
        self->fileManager = [[NSFileManager alloc] init];
        [self->fileManager changeCurrentDirectoryPath:[[NSBundle mainBundle] bundlePath]];
        NSLog(@"%@", self->currentFilesystemDir);
    }
    
    return self;
}

- (NSString *)pwd
{
    return @"/";
}


- (NSString *)listForPath:(NSString *)path error:(NSError **)error
{
    NSMutableString *listString = [[NSMutableString alloc] init];
    
    NSError *listingError;
    
    NSArray *items = [self->fileManager contentsOfDirectoryAtPath:[self->fileManager currentDirectoryPath] error:&listingError];
    
    for (NSString *item in items) {
        NSString *itemPath = [NSString stringWithFormat:@"%@/%@", [self->fileManager currentDirectoryPath], item];
        NSError *readAttributesError;
        NSDictionary *fileAttributes = [self->fileManager attributesOfItemAtPath:item error:&readAttributesError];
        
        BOOL itemIsDirectory;
        [self->fileManager fileExistsAtPath:itemPath isDirectory:&itemIsDirectory];
        
        NSString *modeString = @"-r-xr-xr-x";
        if (itemIsDirectory) {
            modeString = @"dr-xr-xr-x";
        }
        
        NSDate *modificationDate = [fileAttributes valueForKey:@"NSFileModificationDate"];
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"MMM dd HH:mm"];
        NSLog(@"%@", [dateFormatter stringFromDate:modificationDate]);
        NSString *modificationDateString = [dateFormatter stringFromDate:modificationDate];
        
        long long itemSize = [[fileAttributes valueForKey:@"NSFileSize"] longLongValue];
        
        NSString *itemOwner = @"iosdevice";
        NSString *itemGroup = @"group";
        
        NSString *listingLine = [NSString stringWithFormat:@"%@ 1 %@ %@\t\t%lld %@ %@\n", modeString, itemOwner, itemGroup, itemSize, modificationDateString, item];
        [listString appendString:listingLine];
    }
    
    NSLog(@"%@", listString);
    
    return listString;
}


- (BOOL)changeWorkingDirectory:(NSString *)directoryName
{
    NSString *newWorkingDirectory = [NSString stringWithFormat:@"%@%@", [self->fileManager currentDirectoryPath], directoryName];
    
    return [self->fileManager changeCurrentDirectoryPath:newWorkingDirectory];
}


- (NSString *)currentPath
{
    return [self->fileManager currentDirectoryPath];
}

@end
