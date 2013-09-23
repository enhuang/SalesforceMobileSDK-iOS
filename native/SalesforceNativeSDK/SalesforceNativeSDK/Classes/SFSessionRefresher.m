/*
 Copyright (c) 2011, salesforce.com, inc. All rights reserved.
 
 Redistribution and use of this software in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of
 conditions and the following disclaimer in the documentation and/or other materials provided
 with the distribution.
 * Neither the name of salesforce.com, inc. nor the names of its contributors may be used to
 endorse or promote products derived from this software without specific prior written
 permission of salesforce.com, inc.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SFSessionRefresher.h"
#import <SalesforceSDKCore/SalesforceSDKConstants.h>
#import "SFRestAPI.h"
#import <SalesforceSDKCore/SFAccountManager.h>

@interface SFSessionRefresher ()
{
    SFAccountManager *_accountMgr;
}

/**
 * Ensure that the original OAuth coordinator delegate, if any, is restored.
 */
- (void)restoreOAuthDelegate;

/**
 * Do the necessary cleanup following refresh
 */
- (void)cleanupAfterRefresh;

@end


@implementation SFSessionRefresher

@synthesize previousOAuthDelegate = _previousOAuthDelegate;
@synthesize isRefreshing = _isRefreshing;

- (id)init {
    self = [super init];
    if (nil != self) {
        _refreshLock = [[NSLock alloc] init];
        self.isRefreshing = NO;
        _accountMgr = [SFAccountManager sharedInstance];
    }
    
    return self;
}

- (void)dealloc {
    [self restoreOAuthDelegate];
    SFRelease(_refreshLock);
}

#pragma mark - Public

- (void)refreshAccessToken {
    
    if ([_refreshLock tryLock]) {
        //we now own the lock and can go crazy
        self.isRefreshing = YES;
        NSLog(@"Refreshing access token");
        
        // let's refresh the token
        // but first, let's save the previous delegate
        self.previousOAuthDelegate = _accountMgr.oauthDelegate;
        _accountMgr.oauthDelegate = self;
        [_accountMgr.coordinator authenticate];
    }
    //else somebody else owns the lock and will unlock once refresh completes
    
}


#pragma mark - SFOAuthCoordinatorDelegate


- (void)oauthCoordinator:(SFOAuthCoordinator *)coordinator didBeginAuthenticationWithView:(UIWebView *)view {
    NSLog(@"oauthCoordinator:didBeginAuthenticationWithView");    
    // we are in the token exchange flow so this should never happen
    //TODO we should probably hand back control to the original coordinator delegate at this point,
    //since we don't expect to be able to handle this condition!
    [self restoreOAuthDelegate];
    [coordinator stopAuthentication];
    NSError *newError = [NSError errorWithDomain:kSFOAuthErrorDomain code:kSFRestErrorCode userInfo:nil];
    [[SFNetworkEngine sharedInstance] failOperationsWaitingForAccessTokenWithError:newError];
    
    // we are creating a temp view here since the oauth library verifies that the view
    // has a subview after calling oauthCoordinator:didBeginAuthenticationWithView:
    UIView *tempView = [[UIView alloc] initWithFrame:CGRectZero];
    [tempView addSubview:view];    
}

- (void)oauthCoordinatorDidAuthenticate:(SFOAuthCoordinator *)coordinator authInfo:(SFOAuthInfo *)info
{
    NSLog(@"oauthCoordinatorDidAuthenticate, user: %@, authInfo: %@", coordinator.credentials.userId, info);
    
    // The token exchange worked.
    [self restoreOAuthDelegate];
    [[SFRestAPI sharedInstance] setCoordinator:coordinator];
    [self cleanupAfterRefresh];
}

- (void)oauthCoordinator:(SFOAuthCoordinator *)coordinator didFailWithError:(NSError *)error authInfo:(SFOAuthInfo *)info
{
    NSLog(@"oauthCoordinator:didFailWithError: %@, authInfo: %@", error, info);
    
    // oauth error
    [self restoreOAuthDelegate];
    [coordinator stopAuthentication];
    NSError *newError = [NSError errorWithDomain:kSFOAuthErrorDomain code:kSFRestErrorCode userInfo:[error userInfo]];
    [[SFNetworkEngine sharedInstance] failOperationsWaitingForAccessTokenWithError:newError];
    [self cleanupAfterRefresh];
}

#pragma mark - Completion

- (void)restoreOAuthDelegate {
    if (nil != self.previousOAuthDelegate) {
        _accountMgr.oauthDelegate = self.previousOAuthDelegate;
        self.previousOAuthDelegate = nil;
    }
}

- (void)cleanupAfterRefresh {
    self.isRefreshing = NO;
    [_refreshLock unlock];
}

@end
