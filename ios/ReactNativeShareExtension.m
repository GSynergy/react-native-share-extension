#import "ReactNativeShareExtension.h"
#import "React/RCTRootView.h"
#import <MobileCoreServices/MobileCoreServices.h>

#define URL_IDENTIFIER @"public.url"
#define IMAGE_IDENTIFIER @"public.image"
#define KML_IDENTIFIER @"public.kml"
#define VCARD_IDENTIFIER (NSString *) kUTTypeVCard
#define TEXT_IDENTIFIER (NSString *)kUTTypeText

NSExtensionContext* extensionContext;

@implementation ReactNativeShareExtension {
    NSTimer *autoTimer;
    NSString* type;
    NSString* value;
}

- (UIView*) shareView {
    return nil;
}

RCT_EXPORT_MODULE();

- (void)viewDidLoad {
    [super viewDidLoad];

    //object variable for extension doesn't work for react-native. It must be assign to gloabl
    //variable extensionContext. in this way, both exported method can touch extensionContext
    extensionContext = self.extensionContext;

    UIView *rootView = [self shareView];
    if (rootView.backgroundColor == nil) {
        rootView.backgroundColor = [[UIColor alloc] initWithRed:1 green:1 blue:1 alpha:0.1];
    }

    self.view = rootView;
}


RCT_EXPORT_METHOD(close) {
    [extensionContext completeRequestReturningItems:nil
                                  completionHandler:nil];
}



RCT_EXPORT_METHOD(openURL:(NSString *)url) {
  UIApplication *application = [UIApplication sharedApplication];
  NSURL *urlToOpen = [NSURL URLWithString:[url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
  [application openURL:urlToOpen options:@{} completionHandler: nil];
}



RCT_REMAP_METHOD(data,
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    [self extractDataFromContext: extensionContext withCallback:^(NSString* val, NSString* contentType, NSException* err) {
        if(err) {
            reject(@"error", err.description, nil);
        } else {
            resolve(@{
                      @"type": contentType,
                      @"value": val
                      });
        }
    }];
}

- (NSString*) getTmpDirectory {
    NSString *TMP_DIRECTORY = @"react-native-share-extension/";
    NSString *tmpFullPath = [NSTemporaryDirectory() stringByAppendingString:TMP_DIRECTORY];
    
    BOOL isDir;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:tmpFullPath isDirectory:&isDir];
    if (!exists) {
        [[NSFileManager defaultManager] createDirectoryAtPath: tmpFullPath
                                  withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return tmpFullPath;
}

- (void)extractDataFromContext:(NSExtensionContext *)context withCallback:(void(^)(NSString *value, NSString* contentType, NSException *exception))callback {
    @try {
        NSExtensionItem *item = [context.inputItems firstObject];
        NSArray *attachments = item.attachments;

        __block NSItemProvider *urlProvider = nil;
        __block NSItemProvider *imageProvider = nil;
        __block NSItemProvider *textProvider = nil;
        __block NSItemProvider *vCardProvider = nil;
        __block NSItemProvider *kmlProvider = nil;

        [attachments enumerateObjectsUsingBlock:^(NSItemProvider *provider, NSUInteger idx, BOOL *stop) {
            if([provider hasItemConformingToTypeIdentifier:KML_IDENTIFIER]) {
                kmlProvider = provider;
                *stop = YES;
            }
            else if([provider hasItemConformingToTypeIdentifier:VCARD_IDENTIFIER]) {
                vCardProvider = provider;
                *stop = YES;
            }
            else if([provider hasItemConformingToTypeIdentifier:URL_IDENTIFIER]) {
                urlProvider = provider;
                *stop = YES;
            }
            else if ([provider hasItemConformingToTypeIdentifier:IMAGE_IDENTIFIER]){
                imageProvider = provider;
                *stop = YES;
            }
            else if ([provider hasItemConformingToTypeIdentifier:TEXT_IDENTIFIER] && ![provider hasItemConformingToTypeIdentifier:VCARD_IDENTIFIER] && ![provider hasItemConformingToTypeIdentifier:URL_IDENTIFIER ] && ![provider hasItemConformingToTypeIdentifier:KML_IDENTIFIER]){
                 textProvider = provider;
                 *stop = YES;
             }
        }];
        
        if(kmlProvider) {
            [kmlProvider loadItemForTypeIdentifier:KML_IDENTIFIER options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
               NSURL *url = (NSURL *)item;
            
               NSError *writeError;
               NSData *data = [NSData dataWithContentsOfURL:url options:nil error:&writeError];
    
               NSString *tmpDirFullPath = [self getTmpDirectory];
               NSString *filePath = [tmpDirFullPath stringByAppendingString:[[NSUUID UUID] UUIDString]];
               filePath = [filePath stringByAppendingString:@".kml"];
                               
              // save file
              BOOL status = [data writeToFile:filePath atomically:YES];
               if (!status) {
                    callback(@"failed to write",@"error",nil);
                }
                if(callback) {
                    callback(filePath,[filePath pathExtension], nil);
               }
            }];
        } else if(vCardProvider) {
            [vCardProvider loadItemForTypeIdentifier:VCARD_IDENTIFIER options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
                NSData *data = (NSData *)item;
             
                NSString *tmpDirFullPath = [self getTmpDirectory];
                NSString *filePath = [tmpDirFullPath stringByAppendingString:[[NSUUID UUID] UUIDString]];
                filePath = [filePath stringByAppendingString:@".vcf"];
                
                // save file
                BOOL status = [data writeToFile:filePath atomically:YES];
                if (!status) {
                    callback(@"failed to write",@"error",nil);
                }
                if(callback) {
                    callback(filePath,[filePath pathExtension], nil);
                }
            }];
        } else if(urlProvider) {
            [urlProvider loadItemForTypeIdentifier:URL_IDENTIFIER options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
                NSURL *url = (NSURL *)item;

                if(callback) {
                    callback([url absoluteString],@"text/plain", nil);
                }
            }];
        } else if (imageProvider) {
            [imageProvider loadItemForTypeIdentifier:IMAGE_IDENTIFIER options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
                NSURL *url = (NSURL *)item;

                if(callback) {
                    callback([url absoluteString], [[[url absoluteString] pathExtension] lowercaseString], nil);
                }
            }];
        } else if (textProvider) {
            [textProvider loadItemForTypeIdentifier:TEXT_IDENTIFIER options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
                NSString *text = (NSString *)item;

                if(callback) {
                    callback(text, @"text/plain", nil);
                }
            }];
        } else {
            if(callback) {
                callback(nil, nil, [NSException exceptionWithName:@"Error" reason:@"couldn't find provider" userInfo:nil]);
            }
        }
    }
    @catch (NSException *exception) {
        if(callback) {
            callback(nil, nil, exception);
        }
    }
}

@end
