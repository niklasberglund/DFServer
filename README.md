# DFServer #
iOS FTP server library for debugging purposes. Provides easy access for listing and viewing files in your iOS app's bundle. **DO NOT** use DFServer in production.

DFServer currently only supports passive mode and NOT active mode. Make sure your FTP client uses passive mode, or that it's smart enough to try passive mode when active mode fails. 

## Install ##
### Manually ###
Download DFServer and add all files under the `source` directory to your project. Import with:
```
#import "DFServer.h"
```
### Through Cocoapods ###
**Not on Cocoapods quite yet. For now use the manual install method.**

## Examples ##
Note that you import DFServer with `#import <DFServer.h>` if you installed with CocoaPods, but if you installed it manually it's `#import "DFServer.h"`.

### Very basic example ###
```objc
#import "DFServer.h"

self->debugFtpServer = [[DFServer alloc] init]; // self->debugFtpServer is an object of type DFServer
[self->debugFtpServer startListeningOnPort:2121];
```

### Run only in debug builds (highly recommended) ###
Same as above example, but wrapped in `#ifdef DEBUG` like this:
```objc
#import "DFServer.h"

#ifdef DEBUG
	self->debugFtpServer = [[DFServer alloc] init]; // self->debugFtpServer is an object of type DFServer
	[self->debugFtpServer startListeningOnPort:2121];
#endif
```

## Not working? ##
Perhaps you've found a bug. Create an issue here on GitHub: https://github.com/niklasberglund/DFServer/issues
Thanks!

## Contribute ##
Pull requests are welcome. Keep in mind that DFServer is intended to be a compact FTP server for debugging purposes and not intended to be a full-fledged FTP server.
