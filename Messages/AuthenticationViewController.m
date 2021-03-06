//
//  AuthenticationViewController.m
//  Messages
//
//  Created by Jesse Stuart on 9/26/13.
//  Copyright (c) 2013 Boolean Cupcake, LLC. All rights reserved.
//

#import "AuthenticationViewController.h"
#import "AppDelegate.h"
#import "TCPost+CoreData.h"

@import CoreData;

@interface AuthenticationViewController ()

@end

@implementation AuthenticationViewController {
  NSManagedObjectContext *managedObjectContext;

  NSString *currentEntity;
}

- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    // Custom initialization
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];

  [self setTitle:@"Accounts"];

  // Dismiss keyboard when tap outside
  UIGestureRecognizer *tapParent = [[UITapGestureRecognizer alloc]
      initWithTarget:self
              action:@selector(dismissKeyboard:)];
  [self.view addGestureRecognizer:tapParent];

  // Set keyboard type
  self.entityTextField.keyboardType = UIKeyboardTypeURL;

  // Set text field delegate
  self.entityTextField.delegate = self;

  // Set sign in button action
  [self.signinButton addTarget:self
                        action:@selector(signinButtonPressed:)
              forControlEvents:UIControlEventTouchUpInside];

  // Get notified when text field content changes
  [self.entityTextField addTarget:self
                           action:@selector(entityTextFieldChanged:)
                 forControlEvents:UIControlEventEditingChanged];

  TCAppPost *currentAppPost =
      [((AppDelegate *)([UIApplication sharedApplication]
                            .delegate))currentAppPost];

  if (currentAppPost) {
    currentEntity = [currentAppPost.entityURI absoluteString];

    self.entityTextField.text = currentEntity;

    self.signinButton.enabled = NO;

    UIBarButtonItem *signoutButton = [[UIBarButtonItem alloc]
        initWithTitle:@"Sign out"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(signoutButtonPressed:)];
    self.navigationItem.rightBarButtonItem = signoutButton;
  } else {
    NSError *error;
    TCAppPost *appPost = [self firstAppPostWithError:&error];

    if (!error) {
      self.entityTextField.text = [appPost.entityURI absoluteString];

      [self authenticateWithApp:appPost];
    } else {
      // Disable sign in button initially
      self.signinButton.enabled = NO;
    }
  }
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

- (void)dismissKeyboard:(__unused id)sender {
  if ([self.entityTextField isFirstResponder]) {
    [self.entityTextField resignFirstResponder];
  }
}

- (TCAppPost *)firstAppPostWithError:(NSError *__autoreleasing *)error {
  TCAppPost *appPost;

  NSManagedObjectContext *context = [self managedObjectContext];

  NSFetchRequest *fetchRequest =
      [[NSFetchRequest alloc] initWithEntityName:@"TCAppPost"];

  // Configure sort order
  NSSortDescriptor *sortDescriptor =
      [[NSSortDescriptor alloc] initWithKey:@"clientReceivedAt" ascending:NO];
  [fetchRequest setSortDescriptors:@[ sortDescriptor ]];

  NSFetchedResultsController *fetchedResultsController =
      [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                          managedObjectContext:context
                                            sectionNameKeyPath:nil
                                                     cacheName:nil];

  [fetchedResultsController performFetch:error];

  TCAppPostManagedObject *appPostManagedObject;

  if ([fetchedResultsController.fetchedObjects count] > 0) {
    appPostManagedObject =
        [fetchedResultsController.fetchedObjects objectAtIndex:0];
  }

  if ([appPostManagedObject isKindOfClass:TCAppPostManagedObject.class]) {
    appPost = [MTLManagedObjectAdapter modelOfClass:TCAppPost.class
                                  fromManagedObject:appPostManagedObject
                                              error:error];
  } else {
    if (error != NULL) {
      *error =
          [[NSError alloc] initWithDomain:@"App not found" code:1 userInfo:nil];
    }
  }

  return appPost;
}

- (TCAppPost *)appPostForEntity:(NSString *)entity
                          error:(NSError *__autoreleasing *)error {
  TCAppPost *appPost;

  NSManagedObjectContext *context = [self managedObjectContext];

  NSFetchRequest *fetchRequest =
      [[NSFetchRequest alloc] initWithEntityName:@"TCAppPost"];

  // Configure sort order
  NSSortDescriptor *sortDescriptor =
      [[NSSortDescriptor alloc] initWithKey:@"clientReceivedAt" ascending:NO];
  [fetchRequest setSortDescriptors:@[ sortDescriptor ]];

  NSPredicate *predicate =
      [NSPredicate predicateWithFormat:@"entityURI == %@", entity];
  [fetchRequest setPredicate:predicate];

  NSFetchedResultsController *fetchedResultsController =
      [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                          managedObjectContext:context
                                            sectionNameKeyPath:nil
                                                     cacheName:nil];

  [fetchedResultsController performFetch:error];

  TCAppPostManagedObject *appPostManagedObject;

  if ([fetchedResultsController.fetchedObjects count] > 0) {
    appPostManagedObject =
        [fetchedResultsController.fetchedObjects objectAtIndex:0];
  }

  if ([appPostManagedObject isKindOfClass:TCAppPostManagedObject.class]) {
    appPost = [MTLManagedObjectAdapter modelOfClass:TCAppPost.class
                                  fromManagedObject:appPostManagedObject
                                              error:error];
  } else {
    appPost = [[TCAppPost alloc] init];

    appPost.typeURI = @"https://tent.io/types/app/v0#";
    appPost.name = @"Messenger iOS";
    appPost.appDescription = @"Private messenger app for iOS 7+";
    appPost.URL =
        [NSURL URLWithString:@"https://github.com/cupcake/messenger-ios"];
    appPost.redirectURI =
        [NSURL URLWithString:@"cupcakemessenger://oauth/callback"];
    appPost.readTypes = @[ @"https://tent.io/types/relationship/v0" ];
    appPost.writeTypes = @[
      @"https://tent.io/types/conversation/v0",
      @"https://tent.io/types/message/v0"
    ];
    appPost.scopes = @[ @"permissions" ];
  }

  return appPost;
}

- (BOOL)persistAppPost:(TCAppPost *)appPost
                 error:(NSError *__autoreleasing *)error {
  NSManagedObjectContext *context = [self managedObjectContext];

  [MTLManagedObjectAdapter managedObjectFromModel:appPost
                             insertingIntoContext:context
                                            error:error];

  return [context save:error];
}

- (BOOL)persistMetaPost:(TCMetaPost *)metaPost
                  error:(NSError *__autoreleasing *)error {
  NSManagedObjectContext *context = [self managedObjectContext];

  [MTLManagedObjectAdapter managedObjectFromModel:metaPost
                             insertingIntoContext:context
                                            error:error];

  return [context save:error];
}

- (void)signinButtonPressed:(__unused id)sender {
  NSURL *entityURI = [NSURL URLWithString:self.entityTextField.text];

  NSError *error;
  TCAppPost *appPost =
      [self appPostForEntity:[entityURI absoluteString] error:&error];

  if (error) {
    // TODO: Inform user of error
    return;
  }

  if (currentEntity) {
    [self performSignOut];
  }

  [self authenticateWithApp:appPost];
}

- (void)authenticateWithApp:(TCAppPost *)appPost {
  self.signinButton.enabled = NO;

  NSURL *entityURI;

  if (appPost.entityURI) {
    entityURI = appPost.entityURI;
  } else {
    entityURI = [NSURL URLWithString:self.entityTextField.text];
  }

  TentClient *client = [TentClient clientWithEntity:entityURI];
  self.client = client;

  client.metaPost =
      [((AppDelegate *)([UIApplication sharedApplication].delegate))
          fetchMetaPostForEntity:[entityURI absoluteString]
                           error:nil];

  [(AppDelegate *)([UIApplication sharedApplication]
                       .delegate)showNetworkActivityIndicator];

  void (^failureBlock)(AFHTTPRequestOperation * operation, NSError *error) =
      ^(__unused AFHTTPRequestOperation * operation, NSError * error) {
    // TODO: Inform user of error
    NSLog(@"An error occurred: %@", error);

    self.signinButton.enabled = YES;

    [(AppDelegate *)([UIApplication sharedApplication]
                         .delegate)hideNetworkActivityIndicator];
  };

  void (^tokenExchangeSuccessBlock)(TCAppPost * appPost,
                                    TCCredentialsPost *authCredentialsPost) =
      ^(TCAppPost * _appPost,
        __unused TCCredentialsPost * authCredentialsPost) {
    NSError *error;

    [(AppDelegate *)([UIApplication sharedApplication]
                         .delegate)hideNetworkActivityIndicator];

    [self persistAppPost:_appPost error:&error];

    if (error) {
      NSLog(@"error persisting app post: %@", error);
    }

    [self persistMetaPost:client.metaPost error:&error];

    if (error) {
      NSLog(@"error persisting meta post: %@", error);
    }

    [((AppDelegate *)([UIApplication sharedApplication]
                          .delegate))setCurrentAppPost:_appPost];

    [(AppDelegate *)([UIApplication sharedApplication]
                         .delegate)applicationAuthenticated];

    [self performSegueWithIdentifier:@"authenticatedSegue" sender:self];
  };

    [client authenticateWithApp:appPost successBlock:^(TCAppPost *post, NSURL *authURI, NSString *state) {
      // Don't open browser if app is already authenticated
      if (post.authCredentialsPost) {
        tokenExchangeSuccessBlock(post, post.authCredentialsPost);
        return;
      }

      AppDelegate *appDelegate = [[UIApplication sharedApplication] delegate];

      appDelegate.authCallbackBlock = ^(NSURL * callbackURI) {
        [(AppDelegate *)([UIApplication sharedApplication]
                             .delegate)showNetworkActivityIndicator];

        [client exchangeTokenForApp:post
                        callbackURI:callbackURI
                              state:state
                       successBlock:tokenExchangeSuccessBlock
                       failureBlock:failureBlock];
      };

      [(AppDelegate *)([UIApplication sharedApplication]
                           .delegate)hideNetworkActivityIndicator];

      [[UIApplication sharedApplication] openURL:authURI];
    }
failureBlock:failureBlock];
}

- (void)entityTextFieldChanged:(__unused id)sender {
  if ([self validateEntityTextField]) {
    if ([self.entityTextField.text isEqualToString:currentEntity]) {
      // Already authenticated
      self.signinButton.enabled = NO;
    } else {
      self.signinButton.enabled = YES;
    }
  } else {
    self.signinButton.enabled = NO;
  }
}

- (BOOL)validateEntityTextField {
  NSURL *entityURI = [NSURL URLWithString:self.entityTextField.text];

  if (entityURI && entityURI.scheme && entityURI.host) {
    return YES;
  }

  return NO;
}

- (void)signoutButtonPressed:(__unused id)sender {
  [self performSignOut];
}

- (void)performSignOut {
  NSError *error;

  NSManagedObjectContext *context = [self managedObjectContext];

  TCAppPost *appPost = [((AppDelegate *)([UIApplication sharedApplication]
                                             .delegate))currentAppPost];

  TCAppPostManagedObject *appPostManagedObject =
      [MTLManagedObjectAdapter managedObjectFromModel:appPost
                                 insertingIntoContext:context
                                                error:&error];

  if (error) {
    NSLog(@"error with signout action: %@", error);
    return;
  }

  [context deleteObject:appPostManagedObject];

  [context save:&error];

  if (error) {
    NSLog(@"error saving: %@", error);
  }

  self.navigationItem.rightBarButtonItem = nil;

  currentEntity = nil;

  [self entityTextFieldChanged:self];

  // Empty Navigation stack
  [self.navigationController setViewControllers:@[ self ]];

  [(AppDelegate *)([UIApplication sharedApplication]
                       .delegate)applicationDeauthenticated];
}

- (NSManagedObjectContext *)managedObjectContext {
  if (!managedObjectContext) {
    managedObjectContext = [(AppDelegate *)([UIApplication sharedApplication]
                                                .delegate)managedObjectContext];
  }

  return managedObjectContext;
}

#pragma mark - UITextFieldDelegate

@end
