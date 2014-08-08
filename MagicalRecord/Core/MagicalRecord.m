//
//  MagicalRecord.m
//
//  Created by Saul Mora on 3/11/10.
//  Copyright 2010 Magical Panda Software, LLC All rights reserved.
//

#import "CoreData+MagicalRecord.h"

NSString * const kMagicalRecordNSManagedObjectContextDidMergeChangesFromRootContext = @"kMagicalRecordNSManagedObjectContextDidMergeChangesToMainContext";

static MagicalRecord *currentStack_ = nil;
static id iCloudSetupNotificationObserver = nil;

@interface MagicalRecord (Internal)

+ (void) cleanUpErrorHanding;

@end

@interface MagicalRecord ()

@property (nonatomic, strong) NSManagedObjectContext *mainContext;
@property (nonatomic, strong) NSManagedObjectContext *rootSavingContext;
@property (nonatomic, strong) NSPersistentStoreCoordinator *coordinator;

@end

@implementation MagicalRecord

+ (NSMutableDictionary *)stackDictionary
{
    static NSMutableDictionary * _stackDictionary = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _stackDictionary = [NSMutableDictionary dictionary];
    });
    
    return _stackDictionary;
}

+ (void)setCurrentStackWithStoreNamed:(NSString *)storeName
{
    MagicalRecord *stack = [[[self class] stackDictionary] objectForKey:storeName];
    if (!stack) {
        stack = [[self alloc] initStoreWithName:storeName];
        [self setCurrentStack:stack];
    }
}

+ (void)setCurrentStackWithAutoMigratingSqliteStoreNamed:(NSString *)storeName
{
    MagicalRecord *stack = [[[self class] stackDictionary] objectForKey:storeName];
    if (!stack) {
        stack = [[self alloc] initAutoMigratingStoreWithName:storeName];
        [self setCurrentStack:stack];
    }
}

+ (void)setCurrentStackWithInMemoryStoreNamed:(NSString *)storeName
{
    MagicalRecord *stack = [[[self class] stackDictionary] objectForKey:storeName];
    if (!stack) {
        stack = [[self alloc] initAutoMigratingStoreWithName:storeName];
        [self setCurrentStack:stack];
    }
}

+ (void)setCurrentStackWithiCloudContainer:(NSString *)containerID contentNameKey:(NSString *)contentNameKey
                           localStoreNamed:(NSString *)localStoreName cloudStorePathComponent:(NSString *)pathSubcomponent completion:(void(^)(void))completion;
{
    MagicalRecord *stack = [[[self class] stackDictionary] objectForKey:localStoreName];
    if (!stack) {
        stack = [[self alloc] initWithiCloudContainer:containerID contentNameKey:contentNameKey
                                      localStoreNamed:localStoreName cloudStorePathComponent:pathSubcomponent
                                           completion:completion];
        [self setCurrentStack:stack];
    }
}

- (id)initStoreWithName:(NSString *)storeName
{
    self = [super init];
    if (self)
    {
        self.coordinator = [NSPersistentStoreCoordinator MR_coordinatorWithSqliteStoreNamed:storeName];
        [self commonInitWithStoreName:storeName];
    }
    return self;
}

- (id)initAutoMigratingStoreWithName:(NSString *)storeName
{
    self = [super init];
    if (self)
    {
        self.coordinator = [NSPersistentStoreCoordinator MR_coordinatorWithAutoMigratingSqliteStoreNamed:storeName];
        [self commonInitWithStoreName:storeName];
    }
    return self;
}

- (id)initInMemoryStoreWithName:(NSString *)storeName
{
    self = [super init];
    if (self)
    {
        self.coordinator = [NSPersistentStoreCoordinator MR_coordinatorWithInMemoryStore];
        [self commonInitWithStoreName:storeName];
    }
    return self;
}

- (id)initWithiCloudContainer:(NSString *)containerID contentNameKey:(NSString *)contentNameKey
              localStoreNamed:(NSString *)localStoreName cloudStorePathComponent:(NSString *)pathSubcomponent
                   completion:(void(^)(void))completion
{
    self = [super init];
    if (self)
    {
        self.coordinator = [NSPersistentStoreCoordinator MR_coordinatorWithiCloudContainerID:containerID
                                                                              contentNameKey:contentNameKey
                                                                             localStoreNamed:localStoreName
                                                                     cloudStorePathComponent:pathSubcomponent
                                                                                  completion:completion];
        [self commonInitWithStoreName:localStoreName];
    }
    return self;
}

- (void)commonInitWithStoreName:(NSString *)storeName
{
    self.rootSavingContext = [self contextWithStoreCoordinator:self.coordinator];
    self.mainContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    self.mainContext.parentContext = self.rootSavingContext;
    
    [[[self class] stackDictionary] setObject:self forKey:storeName];
    if ([[self class] currentStack] == nil) {
        [[self class] setCurrentStack:self];
    }
}

- (NSManagedObjectContext *) contextWithStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator;
{
	NSManagedObjectContext *context = nil;
    if (coordinator != nil)
	{
        context =  [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [context performBlockAndWait:^{
            [context setPersistentStoreCoordinator:coordinator];
        }];
        MRLog(@"-> Created Context %@", [context MR_workingName]);
    }
    return context;
}


- (void) setRootSavingContext:(NSManagedObjectContext *)context;
{
    if (_rootSavingContext)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:_rootSavingContext];
    }
    
    _rootSavingContext = context;
    [self obtainPermanentIDsBeforeSaving];
    [_rootSavingContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
    [_rootSavingContext MR_setWorkingName:@"BACKGROUND SAVING (ROOT)"];
    MRLog(@"Set Root Saving Context: %@", _rootSavingContext);
}

- (void) setMainContext:(NSManagedObjectContext *)moc
{
    if (_mainContext)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:_mainContext];
    }
    
    NSPersistentStoreCoordinator *coordinator = self.coordinator;
    if (iCloudSetupNotificationObserver)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:iCloudSetupNotificationObserver];
        iCloudSetupNotificationObserver = nil;
    }
    
    if ([MagicalRecord isICloudEnabled])
    {
        [_mainContext MR_stopObservingiCloudChangesInCoordinator:coordinator];
    }
    
    _mainContext = moc;
    [_mainContext MR_setWorkingName:@"DEFAULT"];
    
    if (_mainContext == nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:self.rootSavingContext];
        
    } else if (self.rootSavingContext != nil) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(rootContextChanged:)
                                                     name:NSManagedObjectContextDidSaveNotification
                                                   object:self.rootSavingContext];
    }
    
    [self obtainPermanentIDsBeforeSaving];
    if ([MagicalRecord isICloudEnabled])
    {
        [_mainContext MR_observeiCloudChangesInCoordinator:coordinator];
    }
    else
    {
        // If icloud is NOT enabled at the time of this method being called, listen for it to be setup later, and THEN set up observing cloud changes
        iCloudSetupNotificationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMagicalRecordPSCDidCompleteiCloudSetupNotification
                                                                                            object:nil
                                                                                             queue:[NSOperationQueue mainQueue]
                                                                                        usingBlock:^(NSNotification *note) {
                                                                                            [moc MR_observeiCloudChangesInCoordinator:coordinator];
                                                                                        }];
    }
    MRLog(@"Set Default Context: %@", _mainContext);
}

- (void)rootContextChanged:(NSNotification *)notification
{
    if ([NSThread isMainThread] == NO) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self rootContextChanged:notification];
        });
        
        return;
    }
    
    [self.mainContext mergeChangesFromContextDidSaveNotification:notification];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMagicalRecordNSManagedObjectContextDidMergeChangesFromRootContext object:self.mainContext userInfo:nil];
}


- (void) contextWillSave:(NSNotification *)notification
{
    NSManagedObjectContext *context = [notification object];
    NSSet *insertedObjects = [context insertedObjects];
    
    if ([insertedObjects count])
    {
        MRLog(@"Context %@ is about to save. Obtaining permanent IDs for new %lu inserted objects", [context MR_workingName], (unsigned long)[insertedObjects count]);
        NSError *error = nil;
        BOOL success = [context obtainPermanentIDsForObjects:[insertedObjects allObjects] error:&error];
        if (!success)
        {
            [MagicalRecord handleErrors:error];
        }
    }
}

- (NSPersistentStore *)persistentStore
{
    NSArray *persistentStores = [self.coordinator persistentStores];
    if ([persistentStores count])
    {
        return [persistentStores objectAtIndex:0];
    }
    return nil;
}

- (void) obtainPermanentIDsBeforeSaving;
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contextWillSave:)
                                                 name:NSManagedObjectContextWillSaveNotification
                                               object:self];
    
    
}

+ (void)setCurrentStack:(MagicalRecord *)stack
{
    @synchronized (self)
    {
        currentStack_ = stack;
    }
    MRLog(@"Set Current Stack: %@", [stack description]);
}

+ (instancetype)currentStack
{
    return currentStack_;
}

+ (void) cleanUp
{
    [self cleanUpErrorHanding];
    [[self stackDictionary] removeAllObjects];
}

+ (NSString *) description
{
    MagicalRecord *stack = [self currentStack];
    return [stack description];
}

- (NSString *) description {
    NSMutableString *status = [NSMutableString stringWithFormat:@"Core Data Stack %p: ---- \n", self];
    
    [status appendFormat:@"Model:           %@\n", [[NSManagedObjectModel MR_defaultManagedObjectModel] entityVersionHashesByName]];
    [status appendFormat:@"Coordinator:     %@\n", self.coordinator];
    [status appendFormat:@"Store:           %@\n", self.persistentStore];
    [status appendFormat:@"Default Context: %@\n", [self.mainContext MR_description]];
    [status appendFormat:@"Context Chain:   \n%@\n", [self.mainContext MR_parentChain]];
    
    return status;
}

+ (void) setDefaultModelNamed:(NSString *)modelName;
{
    NSManagedObjectModel *model = [NSManagedObjectModel MR_managedObjectModelNamed:modelName];
    [NSManagedObjectModel MR_setDefaultManagedObjectModel:model];
}

+ (void) setDefaultModelFromClass:(Class)klass;
{
    NSBundle *bundle = [NSBundle bundleForClass:klass];
    NSManagedObjectModel *model = [NSManagedObjectModel mergedModelFromBundles:[NSArray arrayWithObject:bundle]];
    [NSManagedObjectModel MR_setDefaultManagedObjectModel:model];
}

+ (NSString *) defaultStoreName;
{
    NSString *defaultName = [[[NSBundle mainBundle] infoDictionary] valueForKey:(id)kCFBundleNameKey];
    if (defaultName == nil)
    {
        defaultName = kMagicalRecordDefaultStoreFileName;
    }
    if (![defaultName hasSuffix:@"sqlite"]) 
    {
        defaultName = [defaultName stringByAppendingPathExtension:@"sqlite"];
    }

    return defaultName;
}


#pragma mark - initialize

+ (void) initialize;
{
    if (self == [MagicalRecord class]) 
    {
#ifdef MR_SHORTHAND
        [self swizzleShorthandMethods];
#endif
        [self setShouldAutoCreateManagedObjectModel:YES];
        [self setShouldAutoCreateDefaultPersistentStoreCoordinator:NO];
#ifdef DEBUG
        [self setShouldDeleteStoreOnModelMismatch:YES];
#else
        [self setShouldDeleteStoreOnModelMismatch:NO];
#endif
    }
}

@end


