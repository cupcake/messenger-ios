//
//  Contact.m
//  Messages
//
//  Created by Jesse Stuart on 7/28/13.
//  Copyright (c) 2013 Boolean Cupcake, LLC. All rights reserved.
//

#import "Contact.h"
#import "Conversation.h"
#import "Message.h"
#import "AppDelegate.h"
#import "Cursors.h"
#import "TentClient.h"
#import "NSString+URLEncode.h"
#import "TCPost+CoreData.h"

@implementation Contact

@dynamic avatar;
@dynamic avatarIsSigil;
@dynamic name;
@dynamic entityURI;
@dynamic conversations;
@dynamic messages;
@dynamic sectionName;
@dynamic relationshipPost;

+ (void)syncRelationships {
  [[self applicationDelegate] showNetworkActivityIndicator];

  Cursors *cursors =
      ((AppDelegate *)([UIApplication sharedApplication].delegate)).cursors;
  TCAppPost *appPost = [((AppDelegate *)([UIApplication sharedApplication]
                                             .delegate))currentAppPost];

  TCParams *feedParams = [TCParams
      paramsWithDictionary:@{
                             @"types" :
                             @[ @"https://tent.io/types/relationship/v0" ],
                             @"profiles" : @"mentions",
                             @"sort_by" : @"version.received_at"
                           }];

  // since cursor
  [feedParams
      addValue:[cursors stringFromTimestamp:cursors.relationshipCursorTimestamp
                                    version:cursors.relationshipCursorVersionID]
        forKey:@"since"];

  TentClient *client = [TentClient clientWithEntity:appPost.entityURI];
  NSError *error;
  client.metaPost = [[self applicationDelegate]
      fetchMetaPostForEntity:[appPost.entityURI absoluteString]
                       error:&error];
  client.credentialsPost = appPost.authCredentialsPost;

  NSOperationQueue *fetchAvatarsQueue = [[NSOperationQueue alloc] init];
  [fetchAvatarsQueue setSuspended:YES];

  __block BOOL relastionshipsSyncComplete = NO;
  __block int avatarsSyncRemaining = 0;

  NSLock *avatarsSyncRemainingLock = [[NSLock alloc] init];

    [self fetchRelationshipsWithClient:client feedParams:feedParams successBlock:^(__unused AFHTTPRequestOperation *operation, TCResponseEnvelope *responseEnvelope) {

      if ([[responseEnvelope posts] count] == 0)
        return;

      __block NSError *saveError;

      NSManagedObjectContext *context =
          [[self applicationDelegate] managedObjectContext];

      NSDictionary *profiles = [responseEnvelope profiles];

        [[responseEnvelope posts] enumerateObjectsUsingBlock:^(TCPost *post, __unused NSUInteger idx, __unused BOOL *stop) {
          NSString *entity = [((NSDictionary *)[post.mentions objectAtIndex:0])
              objectForKey:@"entity"];
          NSDictionary *profile = [profiles objectForKey:entity];

          if (!profile)
            return;

          NSError *existingContactFetchError;
          Contact *contact =
              [self contactForEntityURI:entity
                                  error:&existingContactFetchError];

          if (!contact) {
            if (existingContactFetchError) {
              NSLog(@"error fetching existing contact: %@",
                    existingContactFetchError);
            }

            contact = [[Contact alloc] initWithEntity:
                                           [NSEntityDescription
                                                        entityForName:@"Contact"
                                               inManagedObjectContext:context]
                       insertIntoManagedObjectContext:context];

            TCPostManagedObject *postManagedObject =
                [MTLManagedObjectAdapter managedObjectFromModel:post
                                           insertingIntoContext:context
                                                          error:&saveError];

            contact.relationshipPost = postManagedObject;
          }

          contact.name = [profile objectForKey:@"name"];

          if (!contact.name) {
            contact.name = entity;
          }

          contact.entityURI = entity;

          contact.sectionName = [contact.name substringToIndex:1];

          __block NSManagedObjectID *contactObjectID = contact.objectID;
          __block NSString *avatarDigest =
              [profile objectForKey:@"avatar_digest"];

          if (contactObjectID) {
            if (avatarDigest) {
              [fetchAvatarsQueue addOperationWithBlock:^{
                 [self fetchAvatarWithContactObjectID:contactObjectID
                                               entity:entity
                                         avatarDigest:avatarDigest
                                               client:client
                                      completionBlock:^{
                                        // Decrement number of avatar requests
                                        // remaining
                                        [avatarsSyncRemainingLock lock];
                                        avatarsSyncRemaining--;
                                        [avatarsSyncRemainingLock unlock];
                                      }];
               }];
            } else {
              [fetchAvatarsQueue addOperationWithBlock:^{
                 [self fetchSigilWithContactObjectID:contactObjectID
                                              entity:entity
                                      operationQueue:client.operationQueue
                                     completionBlock:^{
                                       // Decrement number of avatar requests
                                       // remaining
                                       [avatarsSyncRemainingLock lock];
                                       avatarsSyncRemaining--;
                                       [avatarsSyncRemainingLock unlock];
                                     }];
               }];
            }
          }
        }];

        if (![context hasChanges])
          return;

        if ([[self applicationDelegate] saveContext:context error:&saveError]) {

          NSLock *saveCursorsLock =
              [[self applicationDelegate] saveCursorsLock];

          [saveCursorsLock lock];

          TCPost *referencePost = [[responseEnvelope posts] firstObject];
          NSDate *referenceTimestamp = referencePost.publishedAt;
          NSString *referenceVersionID = referencePost.versionID;

          cursors.relationshipCursorTimestamp = referenceTimestamp;
          cursors.relationshipCursorVersionID = referenceVersionID;

          [cursors saveToPlistWithError:&saveError];

          [saveCursorsLock unlock];
        }
    }
completionBlock:^{
    relastionshipsSyncComplete = YES;
    }];

  // Wait for all requests to finish
  [client.operationQueue addOperationWithBlock:^{
     while (!relastionshipsSyncComplete) {
       [NSThread sleepForTimeInterval:1];
     }

     // Set number of avatar requests remaining
     [avatarsSyncRemainingLock lock];
     avatarsSyncRemaining = (int)[fetchAvatarsQueue operationCount];
     [avatarsSyncRemainingLock unlock];

     // Wait until all relationships are synced before fetching avatars
     [fetchAvatarsQueue setSuspended:NO];

     // Wait until all avatar requests are queued
     [fetchAvatarsQueue waitUntilAllOperationsAreFinished];

     // Wait until all avatar requests/callbacks have completed
     while (avatarsSyncRemaining > 0) {
       [NSThread sleepForTimeInterval:1];
     }
   }];

  // TODO: fetch any missing avatars

  [client.operationQueue waitUntilAllOperationsAreFinished];

  [[self applicationDelegate] hideNetworkActivityIndicator];
}

+ (Contact *)contactForEntityURI:(NSString *)entityURI
                           error:(NSError *__autoreleasing *)error {
  NSManagedObjectContext *context =
      [[self applicationDelegate] managedObjectContext];

  NSFetchRequest *fetchRequest =
      [[NSFetchRequest alloc] initWithEntityName:@"Contact"];

  // Configure sort order
  NSSortDescriptor *sortDescriptor =
      [[NSSortDescriptor alloc] initWithKey:@"name" ascending:NO];
  [fetchRequest setSortDescriptors:@[ sortDescriptor ]];

  NSPredicate *predicate =
      [NSPredicate predicateWithFormat:@"entityURI == %@", entityURI];
  [fetchRequest setPredicate:predicate];

  NSFetchedResultsController *fetchedResultsController =
      [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                          managedObjectContext:context
                                            sectionNameKeyPath:nil
                                                     cacheName:nil];

  [fetchedResultsController performFetch:error];

  if ([fetchedResultsController.fetchedObjects count] == 0) {
    return nil;
  }

  return [fetchedResultsController.fetchedObjects objectAtIndex:0];
}

+ (void)fetchRelationshipsWithClient:(TentClient *)client
                          feedParams:(TCParams *)feedParams
                        successBlock:
                            (void (^)(AFHTTPRequestOperation *operation,
                                      TCResponseEnvelope *responseEnvelope))
    success
                     completionBlock:(void (^)())completion {

    [client postsFeedWithParams:feedParams successBlock:^(AFHTTPRequestOperation *operation, TCResponseEnvelope *responseEnvelope) {
      success(operation, responseEnvelope);

      if ([responseEnvelope isEmpty]) {
        completion();
      } else {
        TCParams *prevPageParams = [responseEnvelope previousPageParams];

        [self fetchRelationshipsWithClient:client
                                feedParams:prevPageParams
                              successBlock:success
                           completionBlock:completion];
      }
    }
failureBlock:
  ^(__unused AFHTTPRequestOperation * operation, NSError * error) {
    NSLog(@"postsFeedWithParams failure: %@", error);

    completion();
  }];
}

+ (void)fetchAvatarWithContactObjectID:(NSManagedObjectID *)contactObjectID
                                entity:(NSString *)entity
                          avatarDigest:(NSString *)avatarDigest
                                client:(TentClient *)client
                       completionBlock:(void (^)())completion {
    [client getAttachmentWithEntity:entity digest:avatarDigest successBlock:^(__unused AFHTTPRequestOperation *operation, NSData *attachmentBinary) {
      NSManagedObjectContext *context =
          [[self applicationDelegate] managedObjectContext];

      Contact *contact = (Contact *)[context objectWithID:contactObjectID];

      contact.avatar = attachmentBinary;
      contact.avatarIsSigil = NO;

      NSError *error;

      [[self applicationDelegate] saveContext:context error:&error];

      if (error) {
        NSLog(@"error saving contact avatar: %@", error);
      }

      completion();
    }
failureBlock:
  ^(__unused AFHTTPRequestOperation * operation, NSError * error) {
    NSLog(@"fetch avatar failure: %@", error);

    [self fetchSigilWithContactObjectID:contactObjectID
                                 entity:entity
                         operationQueue:client.operationQueue
                        completionBlock:completion];
  }];
}

+ (void)fetchSigilWithContactObjectID:(NSManagedObjectID *)contactObjectID
                               entity:(NSString *)entity
                       operationQueue:(NSOperationQueue *)queue
                      completionBlock:(void (^)())completion {

  NSURL *sigilURL = [NSURL
      URLWithString:
          [NSString stringWithFormat:
                        @"https://sigil.cupcake.io/%@?w=288&inverted=true",
                        [entity stringByAddingURLPercentEncoding]]];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:sigilURL];
  AFHTTPRequestOperation *operation =
      [[AFHTTPRequestOperation alloc] initWithRequest:request];

  // Disable default behaviour to use basic auth
  operation.shouldUseCredentialStorage = NO;

    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *op, __unused id responseObject) {
      NSError *error;
      if (![[NSNumber numberWithInteger:op.response.statusCode]
               isEqualToNumber:[NSNumber numberWithInteger:200]]) {
        error = [NSError errorWithDomain:TCInvalidResponseCodeErrorDomain
                                    code:op.response.statusCode
                                userInfo:@{ @"operation" : op }];
        NSLog(@"error fetching sigil: %@", error);

        completion();
        return;
      }

      NSManagedObjectContext *context =
          [[self applicationDelegate] managedObjectContext];

      Contact *contact = (Contact *)[context objectWithID:contactObjectID];

      contact.avatar = op.responseData;
      contact.avatarIsSigil = YES;

      [[self applicationDelegate] saveContext:context error:&error];

      if (error) {
        NSLog(@"error saving contact avatar: %@", error);
      }

      completion();
    }
failure:
  ^(__unused AFHTTPRequestOperation * op, NSError * error) {
    NSLog(@"error fetching sigil: %@", error);

    completion();
  }];

  [queue addOperation:operation];
}

+ (AppDelegate *)applicationDelegate {
  return (AppDelegate *)([UIApplication sharedApplication].delegate);
}

@end
