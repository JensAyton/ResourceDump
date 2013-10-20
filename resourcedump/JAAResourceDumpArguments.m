#import "JAAResourceDumpArguments.h"
#import "JATemplate.h"
#include <getopt.h>


typedef enum: int
{
	kOptionOutput	= 'o',
	kOptionHelp		= '?',
	
	kOptionDone		= -1
} OptionID;


@interface JAAResourceDumpWorkOrder ()

- (id)initWithInputPath:(NSString *)path outputRoot:(NSURL *)outputRoot;

@end


@implementation JAAResourceDumpArguments

- (id)initWithArguments:(const char *[])argv count:(int)argc
{
	if (!(self = [super init]))  return nil;
	
	[self parseOptions:argv count:argc];
	argv += optind;
	argc -= optind;
	
	if (argc > 0)
	{
		[self readInputPaths:argv count:argc];
	}
	
	return self;
}


- (void)parseOptions:(const char *[])argv count:(int)argc
{
	const struct option longOpts[] =
	{
		{ "output",	required_argument,	NULL, kOptionOutput },
		{ "help",	no_argument,		NULL, kOptionHelp },
		{ 0 }
	};
	
	for (;;)
	{
		OptionID option = getopt_long(argc, (char * const *)argv, "o:?", longOpts, NULL);
		switch (option)
		{
			case kOptionOutput:
				[self parseOutputOption:@(optarg)];
				break;
				
			case kOptionHelp:
				_showHelp = true;
				break;
				
			case kOptionDone:
				return;
		}
	}
}


- (void)parseOutputOption:(NSString *)argument
{
	argument = argument.stringByExpandingTildeInPath.stringByStandardizingPath;
	_outputRoot = [NSURL fileURLWithPath:argument];
}


- (void)readInputPaths:(const char *[])argv count:(int)argc
{
	NSMutableArray *workOrders = [NSMutableArray arrayWithCapacity:argc];
	
	for (int i = 0; i < argc; i++)
	{
		JAAResourceDumpWorkOrder *order = [[JAAResourceDumpWorkOrder alloc] initWithInputPath:@(argv[i]) outputRoot:self.outputRoot];
		[workOrders addObject:order];
	}
	
	_workOrders = [workOrders copy];
}

@end


@implementation JAAResourceDumpWorkOrder

- (id)initWithInputPath:(NSString *)path outputRoot:(NSURL *)outputRoot
{
	if (!(self = [super init]))  return nil;
	
	_nominalPath = [path copy];
	
	NSString *absPath = path.stringByExpandingTildeInPath.stringByStandardizingPath;
	_inputURL = [NSURL fileURLWithPath:absPath];
	
	if (outputRoot == nil)
	{
		outputRoot = _inputURL.URLByDeletingLastPathComponent;
	}
	NSString *outputName = [path.lastPathComponent stringByAppendingString:@" Resources"];
	_outputURL = [outputRoot URLByAppendingPathComponent:outputName];
	
	return self;
}


- (NSString *)description
{
	return JATExpand(@"{self|basedesc}{{{1} ({2} -> {3})}}", self, self.nominalPath, self.inputURL.absoluteString, self.outputURL.absoluteString);
}

@end
