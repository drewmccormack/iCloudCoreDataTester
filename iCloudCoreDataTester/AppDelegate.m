
#import "AppDelegate.h"

static NSString * const MCCloudMainStoreFileName = @"com.mentalfaculty.icloudcoredatatester.1";
static NSString * const MCUsingCloudStorageDefault = @"MCUsingCloudStorageDefault";

#warning Fill in a valid team identifier
static NSString * const TeamIdentifier = @"P7BXV6PHLD";


@interface AppDelegate ()

@property (nonatomic, readonly) NSURL *localStoreURL;
@property (nonatomic, readonly) NSURL *cloudStoreURL;
@property (nonatomic, readonly) NSURL *applicationFilesDirectory;

@property (readwrite, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readwrite, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readwrite, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readwrite, assign, nonatomic) BOOL stackIsSetup;
@property (readwrite, assign, nonatomic) BOOL stackIsLoading;

@end


@implementation AppDelegate {
    IBOutlet NSArrayController *notesController;
    IBOutlet NSArrayController *schedulesController;
    MCCloudResetSentinel *sentinel;
    BOOL stackIsSetup;
    BOOL stackIsLoading;
}

@synthesize window = _window;
@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;
@synthesize managedObjectModel = __managedObjectModel;
@synthesize managedObjectContext = __managedObjectContext;
@synthesize stackIsSetup, stackIsLoading;

#pragma mark Initialization

+(void)initialize
{
    [[NSUserDefaults standardUserDefaults] registerDefaults:
        [NSDictionary dictionaryWithObject:(id)kCFBooleanFalse forKey:MCUsingCloudStorageDefault]];
}

-(id)init
{
    self = [super init];
    if ( self ) {
        stackIsSetup = NO;
        stackIsLoading = NO;
        
        // Setup an 'empty' temporary stack, just so there is a MOC for the bound views to bind to.
        self.persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
        self.managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        self.managedObjectContext.persistentStoreCoordinator = self.persistentStoreCoordinator;
    }
    return self;
}

#pragma mark Launching

-(void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Use a temporary sentinel to determine if a reset of cloud data has occurred since last launch
    if ( !self.cloudStoreURL ) [[NSUserDefaults standardUserDefaults] setBool:NO forKey:MCUsingCloudStorageDefault];
    BOOL usingCloudStorage = [[NSUserDefaults standardUserDefaults] boolForKey:MCUsingCloudStorageDefault];
    if ( usingCloudStorage ) {
        MCCloudResetSentinel *tempSentinel = [[MCCloudResetSentinel alloc] initWithCloudStorageURL:self.cloudStoreURL cloudSyncEnabled:YES];
        [tempSentinel checkCurrentDeviceRegistration:^(BOOL deviceIsPresent) {
            if ( !deviceIsPresent ) [self tearDownAfterCloudReset];
            [self setupCoreDataStack:self];
        }];
    }
}

#pragma mark File Locations

-(NSURL *)localStoreURL
{
    return [self.applicationFilesDirectory URLByAppendingPathComponent:@"iCloudCoreDataTester.storedata"];
}

-(NSURL *)cloudStoreURL
{
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSString *ubiquityId = [NSString stringWithFormat:@"%@.%@", TeamIdentifier, bundleId];
    NSURL *ubiquitousURL = [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:ubiquityId];
    NSURL *storeURL = [ubiquitousURL URLByAppendingPathComponent:@"MainStore"];
    return storeURL;
}

-(NSURL *)applicationFilesDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    return [appSupportURL URLByAppendingPathComponent:bundleId];
}

#pragma mark Adding/Removing Objects

-(IBAction)addNote:(id)sender
{
    if ( !self.stackIsSetup ) [self setupCoreDataStack:self];
    
    id newNote = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:self.managedObjectContext];
    
    id newFacet = [NSEntityDescription insertNewObjectForEntityForName:@"Facet" inManagedObjectContext:self.managedObjectContext];
    [newFacet setValue:newNote forKey:@"note"];
    newFacet = [NSEntityDescription insertNewObjectForEntityForName:@"Facet" inManagedObjectContext:self.managedObjectContext];
    [newFacet setValue:newNote forKey:@"note"];
    
    id newPermutation = [NSEntityDescription insertNewObjectForEntityForName:@"Permutation" inManagedObjectContext:self.managedObjectContext];
    [newPermutation setValue:newFacet forKey:@"facet"];
    [newPermutation setValue:newNote forKey:@"note"];
    
    id newSchedule = [NSEntityDescription insertNewObjectForEntityForName:@"ChildSchedule" inManagedObjectContext:self.managedObjectContext];
    [newPermutation setValue:newSchedule forKey:@"schedule"];
}

-(IBAction)changeSchedule:(id)sender
{
    id note = [[notesController selectedObjects] lastObject];
    if ( !note || notesController.selectedObjects.count > 1 ) return;
    
    id newSchedule = [NSEntityDescription insertNewObjectForEntityForName:@"ChildSchedule" inManagedObjectContext:self.managedObjectContext];
    [newSchedule setValue:[[NSProcessInfo processInfo] globallyUniqueString] forKey:@"title"];
    
    id permutation = [[note valueForKey:@"permutations"] anyObject];
    id existingSchedule = [permutation valueForKey:@"schedule"];
    if ( existingSchedule ) [self.managedObjectContext deleteObject:existingSchedule];
    [permutation setValue:newSchedule forKey:@"schedule"];
}

#pragma mark Core Data Stack

// Note that this does not automatically save the existing context.
// If you want that, do it before calling this method.
-(IBAction)tearDownCoreDataStack:(id)sender
{
    if ( !self.stackIsSetup && !self.stackIsLoading ) return;
    
    [sentinel stopMonitoringDevicesList];
    sentinel = nil;
    
    [self.managedObjectContext reset];
    self.managedObjectContext = nil;
    self.managedObjectModel = nil;
    self.persistentStoreCoordinator = nil;
    
    self.stackIsSetup = NO;
    self.stackIsLoading = NO;
}

-(IBAction)setupCoreDataStack:(id)sender
{
    if ( self.stackIsSetup || self.stackIsLoading ) return;
    self.stackIsLoading = YES;
    
    [self makePersistentStoreCoordinator];
        
    __weak AppDelegate *weakSelf = self;
    [self addStoreToPersistentStoreCoordinator:^(BOOL success, NSError *error) {
        if ( !success ) {
            [weakSelf tearDownCoreDataStack:weakSelf];
            [[NSApplication sharedApplication] presentError:error];
        }
        else {
            [weakSelf makeManagedObjectContext];
            
            // Setup a sentinel
            BOOL usingCloudStorage = [[NSUserDefaults standardUserDefaults] boolForKey:MCUsingCloudStorageDefault];
            if ( usingCloudStorage ) {
                weakSelf->sentinel = [[MCCloudResetSentinel alloc] initWithCloudStorageURL:weakSelf.cloudStoreURL cloudSyncEnabled:usingCloudStorage];
                weakSelf->sentinel.delegate = self;
                [weakSelf->sentinel updateDevicesList:NULL];
            }
            
            weakSelf.stackIsSetup = YES;
        }
        weakSelf.stackIsLoading = NO;
    }];
}

-(IBAction)removeLocalFiles:(id)sender
{
    [self tearDownCoreDataStack:self];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:MCUsingCloudStorageDefault];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSFileManager defaultManager] removeItemAtURL:[self applicationFilesDirectory] error:NULL];
}

-(NSManagedObjectModel *)managedObjectModel
{
    if (__managedObjectModel) return __managedObjectModel;	
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"iCloudCoreDataTester" withExtension:@"momd"];
    __managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return __managedObjectModel;
}

-(void)makePersistentStoreCoordinator
{
    NSManagedObjectModel *mom = [self managedObjectModel];
    if (!mom) {
        NSLog(@"%@:%@ No model to generate a store from", [self class], NSStringFromSelector(_cmd));
        return;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *applicationFilesDirectory = [self applicationFilesDirectory];
    NSError *error = nil;
    
    NSDictionary *properties = [applicationFilesDirectory resourceValuesForKeys:[NSArray arrayWithObject:NSURLIsDirectoryKey] error:&error];
    
    if (!properties) {
        BOOL ok = NO;
        if ([error code] == NSFileReadNoSuchFileError) {
            ok = [fileManager createDirectoryAtPath:[applicationFilesDirectory path] withIntermediateDirectories:YES attributes:nil error:&error];
        }
        if (!ok) {
            [[NSApplication sharedApplication] presentError:error];
            return;
        }
    } else {
        if (![[properties objectForKey:NSURLIsDirectoryKey] boolValue]) {
            NSString *failureDescription = [NSString stringWithFormat:@"Expected a folder to store application data, found a file (%@).", [applicationFilesDirectory path]];
            
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            [dict setValue:failureDescription forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:@"MCErrorDomain" code:101 userInfo:dict];
            
            [[NSApplication sharedApplication] presentError:error];
            return;
        }
    }
    
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
    self.persistentStoreCoordinator = coordinator;
    
    // Register as observer for iCloud merge notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(persistentStoreCoordinatorDidMergeCloudChanges:) name:NSPersistentStoreDidImportUbiquitousContentChangesNotification object:coordinator];
}

-(void)addStoreToPersistentStoreCoordinator:(void (^)(BOOL success, NSError *error))completionBlock
{
    if ( completionBlock ) completionBlock = [completionBlock copy];
    dispatch_queue_t completionQueue = dispatch_get_current_queue();
    dispatch_retain(completionQueue);
    
    // Use cloud storage if iCloud is enabled, and the user default is set to YES.
    NSURL *storeURL = self.cloudStoreURL;
    NSURL *url = self.localStoreURL; 
    if ( storeURL == nil ) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:MCUsingCloudStorageDefault];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    // Basic options
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        (id)kCFBooleanTrue, NSMigratePersistentStoresAutomaticallyOption, 
        (id)kCFBooleanTrue, NSInferMappingModelAutomaticallyOption, 
        nil];
    
    // iCloud options
    BOOL usingCloudStorage = [[NSUserDefaults standardUserDefaults] boolForKey:MCUsingCloudStorageDefault];
    if ( usingCloudStorage ) {
        [options addEntriesFromDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
            MCCloudMainStoreFileName, NSPersistentStoreUbiquitousContentNameKey,
            storeURL, NSPersistentStoreUbiquitousContentURLKey, 
            nil]];
    }
    
    // Add store on background queue. With cloud options enabled, it can take a while.
    dispatch_queue_t serialQueue = dispatch_queue_create("pscqueue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(serialQueue, ^{
        NSError *error;
        [self.persistentStoreCoordinator lock];
        id store = [self.persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:options error:&error];
        [self.persistentStoreCoordinator unlock];
            
        dispatch_async(completionQueue, ^{
            completionBlock(nil != store, error);
            dispatch_release(completionQueue);
        });
        
        dispatch_release(serialQueue);
    });
}

-(void)makeManagedObjectContext
{
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    context.persistentStoreCoordinator = self.persistentStoreCoordinator;
    self.managedObjectContext = context;
}

#pragma mark iCloud

-(IBAction)startSyncing:(id)sender
{
    if ( !self.cloudStoreURL ) {
        NSLog(@"iCloud not available. Ubiq URL was nil");
        return;
    }
    
    // Save existing data, and tear down stack
    [self saveAction:self];
    [self tearDownCoreDataStack:self];
    
    // Use sentinel to determine if device was previously syncing.
    // In that case, the only option is to replace the whole cloud container.
    // If the device never synced before, the user can choose to keep the 
    // local or the cloud data.
    MCCloudResetSentinel *tempSentinel = [[MCCloudResetSentinel alloc] initWithCloudStorageURL:self.cloudStoreURL cloudSyncEnabled:NO];
    [tempSentinel stopMonitoringDevicesList];
    [tempSentinel checkCurrentDeviceRegistration:^(BOOL deviceIsPresent) {
        if ( deviceIsPresent ) {
            // Only choice is to move data to the cloud, replacing the existing cloud data.
            // In a production app, you should warn the user, and give them a chance
            // to back out.
            [self migrateStoreToCloud];
        }
        else {
            // Can keep either the cloud data, or the local data at this point
            // In a production app, you could ask the user what they want to keep.
            // Here we will just see if there is cloud data present, and if there is,
            // use that. If there is no cloud data, we'll keep the local data.
            BOOL migrateDataFromCloud = [[NSFileManager defaultManager] fileExistsAtPath:self.cloudStoreURL.path];
            if ( migrateDataFromCloud ) {
                // Already cloud data present, so replace local data with it
                [self removeLocalFiles:self];
            }
            else {
                // No cloud data, so migrate local data to the cloud
                [self migrateStoreToCloud];
            }
        }
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:MCUsingCloudStorageDefault];
        [self setupCoreDataStack:self];
    }];
}

-(void)migrateStoreToCloud
{
    NSError *error;
    NSURL *storeURL = self.localStoreURL;
    NSURL *oldStoreURL = [[self applicationFilesDirectory] URLByAppendingPathComponent:@"OldStore"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // If there is no local store, no need to migrate
    if ( ![fileManager fileExistsAtPath:storeURL.path] ) return;
        
    // Remove any existing old store file left over from a previous migration
    [fileManager removeItemAtURL:oldStoreURL error:NULL];
    
    // Move existing local store aside
    if ( ![fileManager moveItemAtURL:storeURL toURL:oldStoreURL error:&error] ) {
        [[NSApplication sharedApplication] presentError:error];
        return;
    }
    
    // Options for new cloud store
    NSDictionary *localOnlyOptions = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kCFBooleanTrue, NSMigratePersistentStoresAutomaticallyOption, 
        (id)kCFBooleanTrue, NSInferMappingModelAutomaticallyOption, 
        nil];
    NSDictionary *cloudOptions = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kCFBooleanTrue, NSMigratePersistentStoresAutomaticallyOption, 
        (id)kCFBooleanTrue, NSInferMappingModelAutomaticallyOption, 
        MCCloudMainStoreFileName, NSPersistentStoreUbiquitousContentNameKey,
        self.cloudStoreURL, NSPersistentStoreUbiquitousContentURLKey, 
        nil];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
    id oldStore = [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:oldStoreURL options:localOnlyOptions error:&error];
    if ( !oldStore ) {
        // Move back the old store and present the error
        [fileManager moveItemAtURL:oldStoreURL toURL:storeURL error:NULL];
        [[NSApplication sharedApplication] presentError:error];
        return;
    }
        
    // Migrate existing (old) store to new store
    if ( ![coordinator migratePersistentStore:oldStore toURL:storeURL options:cloudOptions withType:NSSQLiteStoreType error:&error] ) {
        [fileManager removeItemAtURL:storeURL error:NULL];
        [fileManager moveItemAtURL:oldStoreURL toURL:storeURL error:NULL];
        [[NSApplication sharedApplication] presentError:error];
        return;
    }
    else {
        [[NSFileManager defaultManager] removeItemAtURL:oldStoreURL error:NULL];
    }
}

-(IBAction)removeCloudFiles:(id)sender
{
    [self saveAction:self];    
    [self tearDownCoreDataStack:self];
    
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:MCUsingCloudStorageDefault];

    NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSURL *storeURL = self.cloudStoreURL;
    if ( !storeURL ) return;
    [coordinator coordinateWritingItemAtURL:storeURL options:NSFileCoordinatorWritingForDeleting error:NULL byAccessor:^(NSURL *newURL) {
        [[NSFileManager defaultManager] removeItemAtURL:newURL error:NULL];
    }];
}

-(void)persistentStoreCoordinatorDidMergeCloudChanges:(NSNotification *)notification
{
    [self.managedObjectContext performBlock:^{        
        [self.managedObjectContext mergeChangesFromContextDidSaveNotification:notification]; 
        [self saveAction:self];
    }];
}

#pragma mark Cloud Sentinel Delegate Methods

-(void)cloudResetSentinelDidDetectReset:(MCCloudResetSentinel *)sentinel
{
    BOOL usingCloudStorage = [[NSUserDefaults standardUserDefaults] boolForKey:MCUsingCloudStorageDefault];
    if ( !usingCloudStorage ) return;
    [self tearDownAfterCloudReset];
    [self setupCoreDataStack:self];
}

-(void)tearDownAfterCloudReset
{
    [self tearDownCoreDataStack:self];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:MCUsingCloudStorageDefault];
    
    NSAlert *alert = [NSAlert alertWithMessageText:@"iCloud syncing has been disabled" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"The iCloud data of this app has been removed or tampered with."];
    [alert runModal];
    
    [self setupCoreDataStack:self];
}

#pragma mark Saving and Quitting

-(IBAction)saveAction:(id)sender
{    
    if ( !self.stackIsSetup ) return;
    [self.managedObjectContext performBlockAndWait:^{
        if (![[self managedObjectContext] commitEditing]) {
            NSLog(@"%@:%@ unable to commit editing before saving", [self class], NSStringFromSelector(_cmd));
        }
        
        NSError *error = nil;
        if (![[self managedObjectContext] save:&error]) {
            NSLog(@"Save error: %@", error);
            [[NSApplication sharedApplication] presentError:error];
        }
    }];
}

-(NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{    
    if (!__managedObjectContext) return NSTerminateNow;
    
    if (![[self managedObjectContext] commitEditing]) {
        NSLog(@"%@:%@ unable to commit editing to terminate", [self class], NSStringFromSelector(_cmd));
        return NSTerminateCancel;
    }
    
    if (![[self managedObjectContext] hasChanges]) {
        return NSTerminateNow;
    }
    
    NSError *error = nil;
    if (![[self managedObjectContext] save:&error]) {
        BOOL result = [sender presentError:error];
        if (result) return NSTerminateCancel;

        NSString *question = NSLocalizedString(@"Could not save changes while quitting. Quit anyway?", @"Quit without saves error question message");
        NSString *info = NSLocalizedString(@"Quitting now will lose any changes you have made since the last successful save", @"Quit without saves error question info");
        NSString *quitButton = NSLocalizedString(@"Quit anyway", @"Quit anyway button title");
        NSString *cancelButton = NSLocalizedString(@"Cancel", @"Cancel button title");
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:question];
        [alert setInformativeText:info];
        [alert addButtonWithTitle:quitButton];
        [alert addButtonWithTitle:cancelButton];

        NSInteger answer = [alert runModal];
        
        if (answer == NSAlertAlternateReturn) return NSTerminateCancel;
    }

    return NSTerminateNow;
}

@end
