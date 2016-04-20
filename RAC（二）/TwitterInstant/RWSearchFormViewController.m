//
//  RWSearchFormViewController.m
//  TwitterInstant
//
//  Created by Colin Eberhardt on 02/12/2013.
//  Copyright (c) 2013 Colin Eberhardt. All rights reserved.
//

#import "RWSearchFormViewController.h"
#import "RWSearchResultsViewController.h"
#import <ReactiveCocoa/RACEXTScope.h>
//#import "RACEXTScope.h"
#import <ReactiveCocoa/ReactiveCocoa.h>
#import <Accounts/Accounts.h>
#import <Social/Social.h>
#import "RWTweet.h"
#import "NSArray+LinqExtensions.h"

typedef NS_ENUM(NSInteger, RWTwitterInstantError) {
  RWTwitterInstantErrorAccessDenied,
  RWTwitterInstantErrorNoTwitterAccounts,
  RWTwitterInstantErrorInvalidResponse
};

static NSString * const RWTwitterInstantDomain = @"TwitterInstant";

@interface RWSearchFormViewController ()

@property (weak, nonatomic) IBOutlet UITextField *searchText;

@property (strong, nonatomic) RWSearchResultsViewController *resultsViewController;

@property (strong, nonatomic) ACAccountStore *accountStore;
@property (strong, nonatomic) ACAccountType *twitterAccountType;

@end

@implementation RWSearchFormViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  self.title = @"Twitter Instant";
  
  [self styleTextField:self.searchText];
  
  self.resultsViewController = self.splitViewController.viewControllers[1];
  
    @weakify(self)
    [[self.searchText.rac_textSignal
      map:^id(NSString *text) {
          return [self isValidSearchText:text] ?
          [UIColor whiteColor] : [UIColor yellowColor];
      }]
     subscribeNext:^(UIColor *color) {
         @strongify(self)
         self.searchText.backgroundColor = color;
     }];
    
//    根据上面所说的，如果你创建了一个管道，但是没有订阅它，这个管道就不会执行，包括任何如doNext: block的附加操作
//    RACSignal*backgroundColorSingal=[self.searchText.rac_textSignal map:^id(NSString *text) {
//        return [self isValidSearchText:text]?[UIColor clearColor]:[UIColor yellowColor];
//        
//        
//        
//    }];
//    RACDisposable *subscription=[backgroundColorSingal subscribeNext:^(UIColor *color) {
//        
//        self.searchText.backgroundColor=color;
//        
//    }];
//    [subscription dispose];
//
    self.accountStore=[[ACAccountStore alloc]init];
    self.twitterAccountType=[self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    
    [[[self requestAccessToTwitterSignal]
      then:^RACSignal *{
          @strongify(self)
          return self.searchText.rac_textSignal;
      }]
     subscribeNext:^(id x) {
         NSLog(@"%@", x);
     } error:^(NSError *error) {
         NSLog(@"An error occurred: %@", error);
     }];
    
    
    [[[[[[self requestAccessToTwitterSignal]
         then:^RACSignal *{
             @strongify(self)
             return self.searchText.rac_textSignal;
         }]
        filter:^BOOL(NSString *text) {
            @strongify(self)
            return [self isValidSearchText:text];
        }]
       flattenMap:^RACStream *(NSString *text) {
           @strongify(self)
           return [self signalForSearchWithText:text];
       }]
      deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(id x) {
         NSLog(@"%@", x);
     } error:^(NSError *error) {
         NSLog(@"An error occurred: %@", error);
     }];
}

- (RACSignal *)requestAccessToTwitterSignal {
  
  // 1 - define an error
//    定义了一个error，当用户拒绝访问时发送
  NSError *accessError = [NSError errorWithDomain:RWTwitterInstantDomain
                                             code:RWTwitterInstantErrorAccessDenied
                                         userInfo:nil];
  
  // 2 - create the signal
//    和第一部分一样，类方法createSignal返回一个RACSignal实例
  @weakify(self)
  return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
    // 3 - request access to twitter
//      通过account store请求访问Twitter。此时用户会看到一个弹框来询问是否允许访问Twitter账户
    @strongify(self)
    [self.accountStore
       requestAccessToAccountsWithType:self.twitterAccountType
         options:nil
      completion:^(BOOL granted, NSError *error) {
          // 4 - handle the response
//          在用户允许或拒绝访问之后，会发送signal事件。如果用户允许访问，会发送一个next事件，紧跟着再发送一个completed事件。如果用户拒绝访问，会发送一个error事件。
          if (!granted) {
            [subscriber sendError:accessError];
          } else {
            [subscriber sendNext:nil];
            [subscriber sendCompleted];
          }
        }];
    return nil;
  }];
}

- (SLRequest *)requestforTwitterSearchWithText:(NSString *)text {
  NSURL *url = [NSURL URLWithString:@"https://api.twitter.com/1.1/search/tweets.json"];
  NSDictionary *params = @{@"q" : text};
  
  SLRequest *request =  [SLRequest requestForServiceType:SLServiceTypeTwitter
                                           requestMethod:SLRequestMethodGET
                                                     URL:url
                                              parameters:params];
  return request;
}

- (RACSignal *)signalForSearchWithText:(NSString *)text {

  // 1 - define the errors
//    首先需要定义2个不同的错误，一个表示用户还没有添加任何Twitter账号，另一个表示在请求过程中发生了错误。
  NSError *noAccountsError = [NSError errorWithDomain:RWTwitterInstantDomain
                                                 code:RWTwitterInstantErrorNoTwitterAccounts
                                             userInfo:nil];
  
  NSError *invalidResponseError = [NSError errorWithDomain:RWTwitterInstantDomain
                                                      code:RWTwitterInstantErrorInvalidResponse
                                                  userInfo:nil];
  
  // 2 - create the signal block
//    和之前的一样，创建一个signal。
  @weakify(self)
  void (^signalBlock)(RACSubject *subject) = ^(RACSubject *subject) {
    @strongify(self);
    
    // 3 - create the request
//      用你之前写的方法，给需要搜索的文本创建一个请求
    SLRequest *request = [self requestforTwitterSearchWithText:text];
    
    // 4 - supply a twitter account
//      查询account store来找到可用的Twitter账号。如果没有账号的话，发送一个error事件。
    NSArray *twitterAccounts = [self.accountStore accountsWithAccountType:self.twitterAccountType];
    if (twitterAccounts.count == 0) {
      [subject sendError:noAccountsError];
      return;
    }
    [request setAccount:[twitterAccounts lastObject]];
    
    // 5 - perform the request
//      执行请求。
    [request performRequestWithHandler: ^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
      if (urlResponse.statusCode == 200) {
        
        // 6 - on success, parse the response
//          在请求成功的事件里（http响应码200），发送一个next事件，返回解析好的JSON数据，然后再发送一个completed事件。
        NSDictionary *timelineData = [NSJSONSerialization JSONObjectWithData:responseData
                                                                     options:NSJSONReadingAllowFragments
                                                                       error:nil];
        [subject sendNext:timelineData];
        [subject sendCompleted];
      }
      else {
        // 7 - send an error on failure
//          在请求失败的事件里，发送一个error事件。
        [subject sendError:invalidResponseError];
      }
    }];
  };
  
  RACSignal *signal = [RACSignal startLazilyWithScheduler:[RACScheduler scheduler]
                                                    block:signalBlock];
  
  return signal;
}



- (BOOL)isValidSearchText:(NSString *)text {
  return text.length > 2;
}

- (void)styleTextField:(UITextField *)textField {
  CALayer *textFieldLayer = textField.layer;
  textFieldLayer.borderColor = [UIColor grayColor].CGColor;
  textFieldLayer.borderWidth = 2.0f;
  textFieldLayer.cornerRadius = 0.0f;
}

@end
