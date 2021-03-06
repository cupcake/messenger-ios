//
//  AuthenticationViewController.h
//  Messages
//
//  Created by Jesse Stuart on 9/26/13.
//  Copyright (c) 2013 Boolean Cupcake, LLC. All rights reserved.
//

@import UIKit;

#import "TentClient.h"

@interface AuthenticationViewController : UIViewController<UITextFieldDelegate>

@property(weak, nonatomic) IBOutlet UITextField *entityTextField;
@property(weak, nonatomic) IBOutlet UIButton *signinButton;

@property(nonatomic) TentClient *client;

@end
