//
//  ChimpKit.m
//  ChimpKit3
//
//  Created by Drew Conner on 1/7/13.
//  Copyright (c) 2013 MailChimp. All rights reserved.
//

#import "ChimpKit.h"


#define kAPI20Endpoint	@"https://%@.api.mailchimp.com/2.0/"
#define kErrorDomain	@"com.MailChimp.ChimpKit.ErrorDomain"


@interface ChimpKit () <NSURLSessionTaskDelegate>

@property (nonatomic, strong, readonly) NSURLSession *urlSession;
@property (nonatomic, strong) NSMutableDictionary *dataTasks;

@end


@implementation ChimpKit

#pragma mark - Class Methods

+ (ChimpKit *)sharedKit {
	static dispatch_once_t pred = 0;
	__strong static ChimpKit *_sharedKit = nil;
	
	dispatch_once(&pred, ^{
		_sharedKit = [[self alloc] init];
		_sharedKit.timeoutInterval = kDefaultTimeoutInterval;
	});
	
	return _sharedKit;
}


#pragma mark - Properties

- (NSURLSession *)urlSession {
	NSURLSession *_urlSession = nil;
	
	if (!_urlSession) {
		_urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
													delegate:self
											   delegateQueue:nil];
	}
	
	return _urlSession;
}

- (void)setApiKey:(NSString *)apiKey {
	_apiKey = apiKey;
	
	if (_apiKey) {
		// Parse out the datacenter and template it into the URL.
		NSArray *apiKeyParts = [_apiKey componentsSeparatedByString:@"-"];
		if ([apiKeyParts count] > 1) {
			self.apiURL = [NSString stringWithFormat:kAPI20Endpoint, [apiKeyParts objectAtIndex:1]];
		} else {
			NSAssert(FALSE, @"Please provide a valid API Key");
		}
	}
}


#pragma mark - API Methods

- (NSUInteger)callApiMethod:(NSString *)aMethod withParams:(NSDictionary *)someParams andCompletionHandler:(ChimpKitRequestCompletionBlock)aHandler {
    return [self callApiMethod:aMethod withApiKey:nil params:someParams andCompletionHandler:aHandler];
}

- (NSUInteger)callApiMethod:(NSString *)aMethod withApiKey:(NSString *)anApiKey params:(NSDictionary *)someParams andCompletionHandler:(ChimpKitRequestCompletionBlock)aHandler {
	if (aHandler == nil) {
		if (self.delegate && [self.delegate respondsToSelector:@selector(methodCall:failedWithError:)]) {
			NSError *error = [NSError errorWithDomain:kErrorDomain code:kChimpKitErrorInvalidCompletionHandler userInfo:nil];
			[self.delegate methodCall:aMethod failedWithError:error];
		}
		
		return nil;
	}
    
	return [self callApiMethod:aMethod withApiKey:anApiKey params:someParams andCompletionHandler:aHandler orDelegate:nil];
}

- (NSUInteger)callApiMethod:(NSString *)aMethod withParams:(NSDictionary *)someParams andDelegate:(id<ChimpKitRequestDelegate>)aDelegate {
    return [self callApiMethod:aMethod withApiKey:nil params:someParams andDelegate:aDelegate];
}

- (NSUInteger)callApiMethod:(NSString *)aMethod withApiKey:(NSString *)anApiKey params:(NSDictionary *)someParams andDelegate:(id<ChimpKitRequestDelegate>)aDelegate {
	if (aDelegate == nil) {
		if (self.delegate && [self.delegate respondsToSelector:@selector(methodCall:failedWithError:)]) {
			NSError *error = [NSError errorWithDomain:kErrorDomain code:kChimpKitErrorInvalidDelegate userInfo:nil];
			[self.delegate methodCall:aMethod failedWithError:error];
		}
		
		return nil;
	}
    
	return [self callApiMethod:aMethod withApiKey:anApiKey params:someParams andCompletionHandler:nil orDelegate:aDelegate];
}

- (NSUInteger)callApiMethod:(NSString *)aMethod withApiKey:(NSString *)anApiKey params:(NSDictionary *)someParams andCompletionHandler:(ChimpKitRequestCompletionBlock)aHandler orDelegate:(id<ChimpKitRequestDelegate>)aDelegate {
	if ((anApiKey == nil) && (self.apiKey == nil)) {
		if (self.delegate && [self.delegate respondsToSelector:@selector(methodCall:failedWithError:)]) {
			NSError *error = [NSError errorWithDomain:kErrorDomain code:kChimpKitErrorInvalidAPIKey userInfo:nil];
			[self.delegate methodCall:aMethod failedWithError:error];
		}
		
		return nil;
	}
	
	NSString *urlString = nil;
	NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:someParams];
	
	if (anApiKey) {
		NSArray *apiKeyParts = [anApiKey componentsSeparatedByString:@"-"];
		if ([apiKeyParts count] > 1) {
			NSString *apiURL = [NSString stringWithFormat:kAPI20Endpoint, [apiKeyParts objectAtIndex:1]];
			urlString = [NSString stringWithFormat:@"%@%@", apiURL, aMethod];
		} else {
            NSError *error = [NSError errorWithDomain:kErrorDomain code:kChimpKitErrorInvalidAPIKey userInfo:nil];

			if (self.delegate && [self.delegate respondsToSelector:@selector(methodCall:failedWithError:)]) {
				[self.delegate methodCall:aMethod failedWithError:error];
			}
            
            if (aHandler) {
                aHandler(nil, nil, error);
            }
			
			return nil;
		}
		
		[params setValue:anApiKey forKey:@"apikey"];
	} else if (self.apiKey) {
		urlString = [NSString stringWithFormat:@"%@%@", self.apiURL, aMethod];
		[params setValue:self.apiKey forKey:@"apikey"];
	}
	
	if (kCKDebug) NSLog(@"URL: %@", urlString);
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:urlString]
																cachePolicy:NSURLRequestUseProtocolCachePolicy
															timeoutInterval:self.timeoutInterval];
	
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:[self encodeRequestParams:params]];
	
	NSURLSessionDataTask *dataTask = [self.urlSession dataTaskWithRequest:request
														completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
															if (aHandler) {
																aHandler(response, data, error);
															} else {
																if (error) {
																	if (aDelegate && [aDelegate respondsToSelector:@selector(ckRequestFailed:andError:)]) {
																		[aDelegate ckRequestFailed:request andError:error];
																	}
																} else {
																	if (aDelegate && [aDelegate respondsToSelector:@selector(ckRequest:didSucceedWithResponse:Data:)]) {
																		[aDelegate ckRequest:request didSucceedWithResponse:response Data:data];
																	}
																}
															}
														}];
	
	[self.dataTasks setObject:dataTask forKey:[NSNumber numberWithUnsignedInteger:[dataTask taskIdentifier]]];
	
	[dataTask resume];
	
	return [dataTask taskIdentifier];
}

- (void)cancelRequestWithIdentifier:(NSUInteger)identifier {
	NSURLSessionDataTask *dataTask = [self.dataTasks objectForKey:[NSNumber numberWithUnsignedInteger:identifier]];
	
	[dataTask cancel];
	
	[self.dataTasks removeObjectForKey:[NSNumber numberWithUnsignedInteger:identifier]];
}


#pragma mark - <NSURLSessionTaskDelegate> Methods

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
	[self.dataTasks removeObjectForKey:[NSNumber numberWithUnsignedInteger:[task taskIdentifier]]];
}


#pragma mark - Private Methods

- (NSMutableData *)encodeRequestParams:(NSDictionary *)params {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    
    NSMutableData *postData = [NSMutableData dataWithData:[jsonString dataUsingEncoding:NSUTF8StringEncoding]];
	
    return postData;
}


@end
