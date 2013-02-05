
#import "AppDelegate.h"
#import "MCPersistentStoreMigrator.h"

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

#pragma mark Launch

-(void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self checkIfCloudDataHasBeenReset:^(BOOL hasBeenReset) {
        if ( hasBeenReset ) {
            [self disableCloudAfterResetAndWarnUser];
            [self convertCloudStoreToLocalOnlyStore:^{
                [self setupCoreDataStack:self];
            }];
        }
        else {
            [self setupCoreDataStack:self];
        }
    }];
}

#pragma mark Files and Directories

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

-(void)removeApplicationDirectory
{
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateWritingItemAtURL:self.applicationFilesDirectory options:NSFileCoordinatorWritingForDeleting error:NULL byAccessor:^(NSURL *newURL) {
        NSFileManager *fm = [[NSFileManager alloc] init];
        [fm removeItemAtURL:newURL error:NULL];
    }];
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
        __strong AppDelegate *strongSelf = weakSelf;
        if ( !success ) {
            [strongSelf tearDownCoreDataStack:strongSelf];
            [[NSApplication sharedApplication] presentError:error];
        }
        else {
            [strongSelf makeManagedObjectContext];
            
            // Setup a sentinel
            BOOL usingCloudStorage = [[NSUserDefaults standardUserDefaults] boolForKey:MCUsingCloudStorageDefault];
            if ( usingCloudStorage ) {
                strongSelf->sentinel = [[MCCloudResetSentinel alloc] initWithCloudStorageURL:strongSelf.cloudStoreURL];
                strongSelf->sentinel.delegate = strongSelf;
                [strongSelf->sentinel updateDevicesList:NULL];
            }
            
            strongSelf.stackIsSetup = YES;
        }
        strongSelf.stackIsLoading = NO;
    }];
}

-(IBAction)removeLocalFiles:(id)sender
{
    [self saveAction:self];
    [self tearDownCoreDataStack:self];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:MCUsingCloudStorageDefault];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self removeApplicationDirectory];
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
        id store = nil;
        int attempts = 0;
        while ( !store && attempts++ < 20 ) {
            sleep(5);
            [self.persistentStoreCoordinator lock];
            store = [self.persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:options error:&error];
            [self.persistentStoreCoordinator unlock];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(nil != store, error);
        });
#if !OS_OBJECT_USE_OBJC
        dispatch_release(serialQueue);
#endif
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

-(void)checkIfCloudDataHasBeenReset:(void (^)(BOOL hasBeenReset))completionBlock
{
    BOOL usingCloudStorage = [[NSUserDefaults standardUserDefaults] boolForKey:MCUsingCloudStorageDefault];
    if ( usingCloudStorage && !self.cloudStoreURL ) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(YES);
        });
        return;
    }
    
    // Use a temporary sentinel to determine if a reset of cloud data has occurred
    if ( usingCloudStorage ) {
        MCCloudResetSentinel *tempSentinel = [[MCCloudResetSentinel alloc] initWithCloudStorageURL:self.cloudStoreURL];
        [tempSentinel stopMonitoringDevicesList];
        [tempSentinel checkCurrentDeviceRegistration:^(BOOL deviceIsPresent) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(!deviceIsPresent);
            });
        }];
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(NO);
        });
    }
}

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
    MCCloudResetSentinel *tempSentinel = [[MCCloudResetSentinel alloc] initWithCloudStorageURL:self.cloudStoreURL];
    [tempSentinel stopMonitoringDevicesList];
    [tempSentinel checkCurrentDeviceRegistration:^(BOOL deviceIsPresent) {
        // This block finishes up after a migration
        void(^postMigrationBlock)(void) = ^{
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:MCUsingCloudStorageDefault];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self setupCoreDataStack:self];
        };
        
        if ( deviceIsPresent ) {
            // Only choice is to move data to the cloud, replacing the existing cloud data.
            // In a production app, you should warn the user, and give them a chance
            // to back out.
            [self migrateStoreToCloud:postMigrationBlock];
        }
        else {
            // Can keep either the cloud data, or the local data at this point
            // In a production app, you could ask the user what they want to keep.
            // Here we will just see if there is cloud data present, and if there is,
            // use that. If there is no cloud data, we'll keep the local data.
            BOOL migrateDataFromCloud = [[NSFileManager defaultManager] fileExistsAtPath:self.cloudStoreURL.path];
            if ( migrateDataFromCloud ) {
                // Already cloud data present, so replace local data with it
                [self migrateStoreFromCloud:postMigrationBlock];
            }
            else {
                // No cloud data, so migrate local data to the cloud
                [self migrateStoreToCloud:postMigrationBlock];
            }
        }
    }];
}

-(void)migrateStoreAtURL:(NSURL *)storeURL fromOptions:(NSDictionary *)sourceOptions toOptions:(NSDictionary *)destinationOptions
{
    // Create URL for a temporary (old) store
    __block NSError *error;
    NSURL *oldStoreURL = [[self applicationFilesDirectory] URLByAppendingPathComponent:@"OldStore"];
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    
    // If there is no local store, no need to migrate
    if ( ![fileManager fileExistsAtPath:storeURL.path] ) return;
    
    // Remove any existing old store file left over from a previous migration
    [fileManager removeItemAtURL:oldStoreURL error:NULL];
    
    // Move existing store aside. Should do this in a coordinated manner.
    __block BOOL success = NO;
    NSFileCoordinator *fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [fileCoordinator coordinateWritingItemAtURL:storeURL options:NSFileCoordinatorWritingForDeleting writingItemAtURL:oldStoreURL options:NSFileCoordinatorWritingForReplacing error:&error byAccessor:^(NSURL *newFromURL, NSURL *newToURL) {
        success = [fileManager moveItemAtURL:newFromURL toURL:newToURL error:&error];
        [fileCoordinator itemAtURL:newFromURL didMoveToURL:newToURL];
    }];
    
    if ( !success ) {
        [[NSApplication sharedApplication] presentError:error];
        return;
    }
    
    // Here we use a migrator to keep memory low. If you have a small store, you could just use
    // the NSPersistentStoreCoordinator method migratePersistentStore:toURL:options:withType:error:
    MCPersistentStoreMigrator *migrator = [[MCPersistentStoreMigrator alloc] initWithManagedObjectModel:self.managedObjectModel sourceStoreURL:oldStoreURL destinationStoreURL:storeURL];
    migrator.sourceStoreOptions = sourceOptions;
    migrator.destinationStoreOptions = destinationOptions;
    
    // Begin migration
    BOOL migrationSucceeded = YES;
    [migrator beginMigration];
    
    // Migrate all entities. Relationships are always followed, unless they are 'snipped'.
    // To demonstrate that you can 'snip' a object graph up into sub-graphs, to avoid migrating
    // everything at once, we here snip a few relationships so that only Note and Facet objects are migrated first.
    // You can only snip optional relationships, otherwise validation will fail when saving.
    // Batch size of 0 is infinite, ie, no batching.
    [migrator snipRelationship:@"permutations" inEntity:@"Note"];
    [migrator snipRelationship:@"permutations" inEntity:@"Facet"];
    migrationSucceeded &= [migrator migrateEntityWithName:@"Note" batchSize:0 save:YES error:&error];
    
    // Migrate the Permutations (and connected MOs) in now. Batches of 10 at a time.
    migrationSucceeded &= [migrator migrateEntityWithName:@"Permutation" batchSize:10 save:YES error:&error];
    
    // End migration
    [migrator endMigration];
    
    // Clean up
    if ( !migrationSucceeded ) {
        [fileManager removeItemAtURL:storeURL error:NULL];
        [fileManager moveItemAtURL:oldStoreURL toURL:storeURL error:NULL];
        [[NSApplication sharedApplication] presentError:error];
        return;
    }
    else {
        [fileManager removeItemAtURL:oldStoreURL error:NULL];
    }
}

-(void)migrateStoreFromCloud:(void(^)(void))completionBlock
{ 
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        // Simply remove the local store file. Next setup, a new store will be created
        // and populated with data from iCloud.
        [self removeApplicationDirectory];
        
        // Complete
        dispatch_async(dispatch_get_main_queue(), completionBlock);
    });
}

-(void)migrateStoreToCloud:(void(^)(void))completionBlock
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        // Remove cloud files
        [self removeCloudData];
        
        // Options for new cloud store
        NSDictionary *localOnlyOptions = @{
           NSMigratePersistentStoresAutomaticallyOption: @YES,
           NSInferMappingModelAutomaticallyOption: @YES,
           NSReadOnlyPersistentStoreOption: @YES
        };
        NSDictionary *cloudOptions = @{
           NSMigratePersistentStoresAutomaticallyOption: @YES,
           NSInferMappingModelAutomaticallyOption: @YES,
           NSPersistentStoreUbiquitousContentNameKey: MCCloudMainStoreFileName,
           NSPersistentStoreUbiquitousContentURLKey: self.cloudStoreURL
        };
        
        // Migrate in place
        [self migrateStoreAtURL:self.localStoreURL fromOptions:localOnlyOptions toOptions:cloudOptions];
        
        // Complete
        dispatch_async(dispatch_get_main_queue(), completionBlock);
    });
}

-(void)convertCloudStoreToLocalOnlyStore:(void(^)(void))completionBlock
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        // Store options for migration
        NSDictionary *localOnlyOptions = @{
           NSMigratePersistentStoresAutomaticallyOption: @YES,
           NSInferMappingModelAutomaticallyOption: @YES,
        };
        NSDictionary *cloudOptions = @{
           NSMigratePersistentStoresAutomaticallyOption: @YES,
           NSInferMappingModelAutomaticallyOption: @YES,
           NSPersistentStoreUbiquitousContentNameKey: MCCloudMainStoreFileName,
           NSPersistentStoreUbiquitousContentURLKey: self.cloudStoreURL,
           NSReadOnlyPersistentStoreOption: @YES
        };
        
        // Migrate in place
        [self migrateStoreAtURL:self.localStoreURL fromOptions:cloudOptions toOptions:localOnlyOptions];
        
        // Complete
        dispatch_async(dispatch_get_main_queue(), completionBlock);
    });
}

-(void)removeCloudData
{
    NSURL *storeURL = self.cloudStoreURL;
    if ( !storeURL ) return;
    
    NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    
    // Iterate over subpaths and delete
    NSString *path = storeURL.path;
    NSArray *subPaths = [fileManager subpathsOfDirectoryAtPath:path error:NULL];
    for ( NSString *subPath in subPaths ) {
        NSString *fullPath = [path stringByAppendingPathComponent:subPath];
        [coordinator coordinateWritingItemAtURL:[NSURL fileURLWithPath:fullPath] options:NSFileCoordinatorWritingForDeleting error:NULL byAccessor:^(NSURL *newURL) {
            [fileManager removeItemAtURL:newURL error:NULL];
        }];
    }
    
    // Delete the root directory too
    [coordinator coordinateWritingItemAtURL:storeURL options:NSFileCoordinatorWritingForDeleting error:NULL byAccessor:^(NSURL *newURL) {
        [fileManager removeItemAtURL:newURL error:NULL];
    }];
}

-(IBAction)removeCloudFiles:(id)sender
{
    [self saveAction:self];    
    [self tearDownCoreDataStack:self];
    
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:MCUsingCloudStorageDefault];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self removeCloudData];
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
    [self tearDownCoreDataStack:self];
    [self disableCloudAfterResetAndWarnUser];
    [self convertCloudStoreToLocalOnlyStore:^{
        [self setupCoreDataStack:self];
    }];
}

-(void)disableCloudAfterResetAndWarnUser
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:MCUsingCloudStorageDefault];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSAlert *alert = [NSAlert alertWithMessageText:@"iCloud syncing has been disabled" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"The iCloud data of this app has been removed or tampered with."];
    [alert runModal];
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
