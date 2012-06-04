
#import <Cocoa/Cocoa.h>
#import "MCCloudResetSentinel.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, MCCloudResetSentinelDelegate>

@property (assign) IBOutlet NSWindow *window;

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, assign, nonatomic) BOOL stackIsSetup;
@property (readonly, assign, nonatomic) BOOL stackIsLoading;

- (IBAction)saveAction:(id)sender;

@end
