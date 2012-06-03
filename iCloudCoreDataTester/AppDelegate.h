
#import <Cocoa/Cocoa.h>
#import "MCCloudResetSentinel.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, MCCloudResetSentinelDelegate>

@property (assign) IBOutlet NSWindow *window;

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;

- (IBAction)saveAction:(id)sender;

@end
