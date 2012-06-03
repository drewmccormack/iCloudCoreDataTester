
#import <Cocoa/Cocoa.h>
#import "MCCloudResetSentinel.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, MCCloudResetSentinelDelegate>

@property (assign) IBOutlet NSWindow *window;

@property (readwrite, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readwrite, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readwrite, strong, nonatomic) NSManagedObjectContext *managedObjectContext;

- (IBAction)saveAction:(id)sender;

@end
