#import <Foundation/Foundation.h>


/**
 * JAAResourceDumpWorkOrder represents an input file, output path pair to
 * process.
 */
@interface JAAResourceDumpWorkOrder: NSObject

/// The path as provided at the command line.
@property (readonly) NSString *nominalPath;

/// The resolved input file location.
@property (readonly) NSURL *inputURL;

/// The resolved output file location, taking any -o option into account.
@property (readonly) NSURL *outputURL;

@end


@interface JAAResourceDumpArguments: NSObject

- (id)initWithArguments:(const char *[])argv count:(int)argc;

@property (readonly) bool showHelp;
@property (readonly) NSArray *workOrders;
@property (readonly) NSURL *outputRoot;

@end
