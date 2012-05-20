//
//  AppDelegate.m
//  iCloudCoreDataTester
//
//  Created by Drew McCormack on 15/03/12.
//  Copyright (c) 2012 The Mental Faculty. All rights reserved.
//

#import "AppDelegate.h"

static NSString * const MCCloudMainStoreFileName = @"com.mentalfaculty.icloudcoredatatester.1";
static NSString * const UsingCloudStorageDefault = @"UsingCloudStorageDefault";

#warning Fill in a valid team identifier
static NSString * const TeamIdentifier = @"XXXXXXXXXX";


@interface AppDelegate ()

@property (nonatomic, readonly) NSURL *localStoreURL;
@property (nonatomic, readonly) NSURL *cloudStoreURL;
@property (nonatomic, readonly) NSURL *applicationFilesDirectory;

@end

@implementation AppDelegate {
    IBOutlet NSArrayController *notesController;
    IBOutlet NSArrayController *schedulesController;
    BOOL stackIsSetup;
}

@synthesize window = _window;
@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;
@synthesize managedObjectModel = __managedObjectModel;
@synthesize managedObjectContext = __managedObjectContext;

#pragma mark Initialization

-(id)init
{
    self = [super init];
    stackIsSetup = YES;
    return self;
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
    id newNote = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:self.managedObjectContext];
    id newFacet = [NSEntityDescription insertNewObjectForEntityForName:@"Facet" inManagedObjectContext:self.managedObjectContext];
    [newFacet setValue:newNote forKey:@"note"];
    newFacet = [NSEntityDescription insertNewObjectForEntityForName:@"Facet" inManagedObjectContext:self.managedObjectContext];
    [newFacet setValue:newNote forKey:@"note"];
    id newPermutation = [NSEntityDescription insertNewObjectForEntityForName:@"Permutation" inManagedObjectContext:self.managedObjectContext];
    [newPermutation setValue:newFacet forKey:@"facet"];
    [newPermutation setValue:newNote forKey:@"note"];
}

-(IBAction)addSchedule:(id)sender
{
    id note = [[notesController selectedObjects] lastObject];
    if ( !note || notesController.selectedObjects.count > 1 ) return;
    [self.managedObjectContext processPendingChanges];
    id newSchedule = [NSEntityDescription insertNewObjectForEntityForName:@"ChildSchedule" inManagedObjectContext:self.managedObjectContext];
    id permutation = [[note valueForKey:@"permutations"] anyObject];
    id existingSchedule = [permutation valueForKey:@"schedule"];
    if ( existingSchedule ) [self.managedObjectContext deleteObject:existingSchedule];
    [permutation setValue:newSchedule forKey:@"schedule"];
    [self.managedObjectContext processPendingChanges];
}

-(IBAction)removeSchedule:(id)sender
{
    NSArray *permutations = [schedulesController selectedObjects];
    for ( id perm in permutations ) {
        id schedule = [perm valueForKey:@"schedule"];
        [perm setValue:nil forKey:@"note"];
        [self.managedObjectContext deleteObject:schedule];
    }
}

#pragma mark Core Data Stack

-(IBAction)tearDownCoreDataStack:(id)sender
{
    if ( !stackIsSetup ) return;
    stackIsSetup = NO;
    [self.managedObjectContext save:NULL];
    [self.managedObjectContext reset];
    self.managedObjectContext = nil;
    self.managedObjectModel = nil;
    self.persistentStoreCoordinator = nil;
}

-(IBAction)setupCoreDataStack:(id)sender
{
    if ( stackIsSetup ) return;
    stackIsSetup = YES;
    [self willChangeValueForKey:@"managedObjectContext"];
    [self didChangeValueForKey:@"managedObjectContext"];
}

-(IBAction)removeLocalFiles:(id)sender
{
    [self tearDownCoreDataStack:self];
    [[NSFileManager defaultManager] removeItemAtURL:[self applicationFilesDirectory] error:NULL];
}

-(NSManagedObjectModel *)managedObjectModel
{
    if (__managedObjectModel) {
        return __managedObjectModel;
    }
	
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"iCloudCoreDataTester" withExtension:@"momd"];
    __managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return __managedObjectModel;
}

-(NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (__persistentStoreCoordinator) {
        return __persistentStoreCoordinator;
    }    
    
    NSManagedObjectModel *mom = [self managedObjectModel];
    if (!mom) {
        NSLog(@"%@:%@ No model to generate a store from", [self class], NSStringFromSelector(_cmd));
        return nil;
    }
    
    NSURL *storeURL = self.cloudStoreURL;
    BOOL usingCloudStorage = [[NSUserDefaults standardUserDefaults] boolForKey:UsingCloudStorageDefault];
    usingCloudStorage &= storeURL != nil;
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                    (id)kCFBooleanTrue, NSMigratePersistentStoresAutomaticallyOption, 
                                    (id)kCFBooleanTrue, NSInferMappingModelAutomaticallyOption, 
                                    nil];
    if ( usingCloudStorage ) {
        [options addEntriesFromDictionary:[NSDictionary dictionaryWithObjectsAndKeys:
                                           MCCloudMainStoreFileName, NSPersistentStoreUbiquitousContentNameKey,
                                           storeURL, NSPersistentStoreUbiquitousContentURLKey, 
                                           nil]];
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
            return nil;
        }
    } else {
        if (![[properties objectForKey:NSURLIsDirectoryKey] boolValue]) {
            // Customize and localize this error.
            NSString *failureDescription = [NSString stringWithFormat:@"Expected a folder to store application data, found a file (%@).", [applicationFilesDirectory path]];
            
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            [dict setValue:failureDescription forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN" code:101 userInfo:dict];
            
            [[NSApplication sharedApplication] presentError:error];
            return nil;
        }
    }
    
    NSURL *url = self.localStoreURL; 
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
    if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:options error:&error]) {
        [[NSApplication sharedApplication] presentError:error];
        return nil;
    }
    __persistentStoreCoordinator = coordinator;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(persistentStoreCoordinatorDidMergeCloudChanges:) name:NSPersistentStoreDidImportUbiquitousContentChangesNotification object:coordinator];
    
    return __persistentStoreCoordinator;
}

#pragma mark iCloud

-(IBAction)startSyncing:(id)sender
{
    [self tearDownCoreDataStack:self];
    
    BOOL migrateDataFromCloud = [[NSFileManager defaultManager] fileExistsAtPath:self.cloudStoreURL.path];
    if ( migrateDataFromCloud ) {
        // Already cloud data present, so replace local data with it
        [self removeLocalFiles:self];
    }
    else {
        // No cloud data, so migrate local data to the cloud
        [self migrateStoreToCloud];
    }
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:UsingCloudStorageDefault];
    [self setupCoreDataStack:self];
}

-(void)migrateStoreToCloud
{
    NSError *error;
    NSURL *storeURL = self.localStoreURL;
    NSURL *oldStoreURL = [[self applicationFilesDirectory] URLByAppendingPathComponent:@"OldStore"];
    
    // If there is no local store, no need to migrate
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:storeURL.path] ) return;
        
    // Remove any existing old store file left over from a previous migration
    [[NSFileManager defaultManager] removeItemAtURL:oldStoreURL error:NULL];
    
    // Move existing local store aside
    if ( ![[NSFileManager defaultManager] moveItemAtURL:storeURL toURL:oldStoreURL error:&error] ) {
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
        [[NSApplication sharedApplication] presentError:error];
        return;
    }
        
    // Migrate existing (old) store to new store
    if ( ![coordinator migratePersistentStore:oldStore toURL:storeURL options:cloudOptions withType:NSSQLiteStoreType error:&error] ) {
        [[NSApplication sharedApplication] presentError:error];
    }
    else {
        [[NSFileManager defaultManager] removeItemAtURL:oldStoreURL error:NULL];
    }
}

-(IBAction)removeCloudFiles:(id)sender
{
    [self tearDownCoreDataStack:self];
    
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:UsingCloudStorageDefault];

    NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSURL *storeURL = self.cloudStoreURL;
    if ( !storeURL ) return;
    [coordinator coordinateWritingItemAtURL:storeURL options:NSFileCoordinatorWritingForDeleting error:NULL byAccessor:^(NSURL *newURL) {
        [[NSFileManager defaultManager] removeItemAtURL:newURL error:nil];
    }];
}

-(void)persistentStoreCoordinatorDidMergeCloudChanges:(NSNotification *)notification
{
    // Notification contains object ids. The merge method expects objects, so need to convert.
    [self.managedObjectContext performBlock:^{        
        [self.managedObjectContext mergeChangesFromContextDidSaveNotification:notification]; 
        
        NSError *error;
        if ( ![self.managedObjectContext save:&error] ) {
            [NSApp presentError:error];
        }
    }];
}

-(NSManagedObjectContext *)managedObjectContext
{
    if ( !stackIsSetup ) return nil;
    
    if (__managedObjectContext) {
        return __managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (!coordinator) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        [dict setValue:@"Failed to initialize the store" forKey:NSLocalizedDescriptionKey];
        [dict setValue:@"There was an error building up the data file." forKey:NSLocalizedFailureReasonErrorKey];
        NSError *error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN" code:9999 userInfo:dict];
        [[NSApplication sharedApplication] presentError:error];
        return nil;
    }
    __managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [__managedObjectContext setPersistentStoreCoordinator:coordinator];
    __managedObjectContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;

    return __managedObjectContext;
}

#pragma mark Saving and Quitting

-(IBAction)saveAction:(id)sender
{    
    [self.managedObjectContext performBlock:^{
        if (![[self managedObjectContext] commitEditing]) {
            NSLog(@"%@:%@ unable to commit editing before saving", [self class], NSStringFromSelector(_cmd));
        }
        
        NSError *error = nil;
        if (![[self managedObjectContext] save:&error]) {
            [[NSApplication sharedApplication] presentError:error];
        }
    }];
}

-(NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{    
    if (!__managedObjectContext) {
        return NSTerminateNow;
    }
    
    if (![[self managedObjectContext] commitEditing]) {
        NSLog(@"%@:%@ unable to commit editing to terminate", [self class], NSStringFromSelector(_cmd));
        return NSTerminateCancel;
    }
    
    if (![[self managedObjectContext] hasChanges]) {
        return NSTerminateNow;
    }
    
    NSError *error = nil;
    if (![[self managedObjectContext] save:&error]) {

        // Customize this code block to include application-specific recovery steps.              
        BOOL result = [sender presentError:error];
        if (result) {
            return NSTerminateCancel;
        }

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
        
        if (answer == NSAlertAlternateReturn) {
            return NSTerminateCancel;
        }
    }

    return NSTerminateNow;
}

@end
