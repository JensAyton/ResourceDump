#import <Foundation/Foundation.h>
#import "JATemplate.h"
#import "JAAResourceDumpArguments.h"


static void PrintHelp(void);
static void PerformWorkOrder(JAAResourceDumpWorkOrder *order);
static void WriteResourcesFromFork(JAAResourceDumpWorkOrder *order, NSString *forkName, FSRef *fileRef, HFSUniStr255 formalForkName);
static void WriteResourcesFromCurrentFile(JAAResourceDumpWorkOrder *order, NSString *forkName);
static void WriteResourcesOfTypeFromCurrentFile(JAAResourceDumpWorkOrder *order, NSString *forkName, ResType type);
static void WriteOneResource(JAAResourceDumpWorkOrder *order, NSString *forkName, Handle resource);


#define JATErrPrint(TEMPLATE, ...) fputs([JATExpand(TEMPLATE, __VA_ARGS__) UTF8String], stderr)
static NSString *ExtensionForResourceType(NSString *resourceTypeName);
static NSString *StringFromResType(ResType type);
static NSString *StringFromPascalString(ConstStr255Param pstring);


int main(int argc, const char *argv[])
{
	@autoreleasepool
	{
		JAAResourceDumpArguments *args = [[JAAResourceDumpArguments alloc] initWithArguments:argv count:argc];
		
		if (args.showHelp || args.workOrders == 0)  PrintHelp();
		
		for (JAAResourceDumpWorkOrder *order in args.workOrders)
		{
			PerformWorkOrder(order);
		}
	}
    return 0;
}


static void PrintHelp(void)
{
	JATPrint(@"Usage:\n    resourcedump [-o outputDirectory] resourceFile [...]\n");
}


static void PerformWorkOrder(JAAResourceDumpWorkOrder *order)
{
	NSString *path = order.nominalPath;
	
	FSRef fileRef;
	bool gotFileRef = CFURLGetFSRef((__bridge CFURLRef)order.inputURL, &fileRef);
	if (!gotFileRef)
	{
		JATErrPrint(@"Could not create a file reference to {path}.\n", path);
		exit(EXIT_FAILURE);
	}
	
	HFSUniStr255 forkName;
	FSGetDataForkName(&forkName);
	WriteResourcesFromFork(order, @"Data Fork", &fileRef, forkName);
	FSGetResourceForkName(&forkName);
	WriteResourcesFromFork(order, @"Resource Fork", &fileRef, forkName);
}


static void WriteResourcesFromFork(JAAResourceDumpWorkOrder *order, NSString *forkName, FSRef *fileRef, HFSUniStr255 formalForkName)
{
	ResFileRefNum refNum;
	OSErr status = FSOpenResourceFile(fileRef, formalForkName.length, formalForkName.unicode, fsRdPerm, &refNum);
	if (status != noErr)
	{
		if (status == eofErr || status == mapReadErr)  return;	// Not a resource file.
		
		NSString *errorString = @(GetMacOSStatusCommentString(status));
		if (errorString.length == 0)  errorString = JATExpand(@"OS error {status}", status);
		
		NSString *path = order.nominalPath;
		JATErrPrint(@"Could not open resource file {path}: {errorString}\n", path, errorString);
		exit(EXIT_FAILURE);
	}
	
	WriteResourcesFromCurrentFile(order, forkName);
	
	CloseResFile(refNum);
}


static void WriteResourcesFromCurrentFile(JAAResourceDumpWorkOrder *order, NSString *forkName)
{
	ResourceCount iter, count = Count1Types();
	for (iter = 1; iter <= count; iter++)
	{
		ResType type;
		Get1IndType(&type, iter);
		
		WriteResourcesOfTypeFromCurrentFile(order, forkName, type);
	}
}


static void WriteResourcesOfTypeFromCurrentFile(JAAResourceDumpWorkOrder *order, NSString *forkName, ResType type)
{
	ResourceCount iter, count = Count1Resources(type);
	for (iter = 1; iter <= count; iter++)
	{
		Handle resource = Get1IndResource(type, iter);
		
		WriteOneResource(order, forkName, resource);
	}
}


static void WriteOneResource(JAAResourceDumpWorkOrder *order, NSString *forkName, Handle resource)
{
	ResType resourceType;
	ResID resourceID;
	Str255 resourceName;
	GetResInfo(resource, &resourceID, &resourceType, resourceName);
	
	NSString *typeName = StringFromResType(resourceType);
	NSString *fileName;
	if (resourceName[0] == 0)  fileName = JATExpand(@"{resourceID|num:noloc}", resourceID);
	else  fileName = JATExpand(@"{resourceID|num:noloc} – “{1}”", resourceID, StringFromPascalString(resourceName));
	
	NSString *fileExtension = ExtensionForResourceType(typeName);
	if (fileExtension != nil)  fileName = [fileName stringByAppendingPathExtension:fileExtension];
	
	NSURL *typeDirectory = [order.outputURL URLByAppendingPathComponent:forkName];
	typeDirectory = [typeDirectory URLByAppendingPathComponent:typeName];
	NSError *error;
	if (![NSFileManager.defaultManager createDirectoryAtURL:typeDirectory withIntermediateDirectories:YES attributes:nil error:&error])
	{
		JATErrPrint(@"Could not create directory {typeDirectory}: {error}\n", typeDirectory, error);
		exit(EXIT_FAILURE);
	}
	
	NSURL *fileURL = [typeDirectory URLByAppendingPathComponent:fileName];
	NSData *data = [NSData dataWithBytes:*resource length:GetHandleSize(resource)];
	
	if (![data writeToURL:fileURL options:NSDataWritingAtomic error:&error])
	{
		JATErrPrint(@"Could not write {typeName}/{fileName}: {error}\n", typeName, fileName, error);
		exit(EXIT_FAILURE);
	}
}


NSString *ExtensionForResourceType(NSString *resourceTypeName)
{
	NSDictionary *knownUTIs =
	@{
		@"'TEXT'": @"public.text",
		// PICT is disabled because it requires special handling, namely writing a block of 512 bytes of zeroes before the resource data.
	//	@"'PICT'": @"com.apple.pict",
		@"'PNG '": @"public.png",
		@"'PNGf'": @"public.png",
		@"'GIF '": @"public.png",
		@"'GIFf'": @"public.png",
		@"'JPEG'": @"public.jpeg",
		@"'JFIF'": @"public.jpeg",
		@"'TIFF'": @"public.tiff",
		@"'icns'": @"com.apple.icns",
	};
	
	NSString *uti = knownUTIs[resourceTypeName];
	if (uti == nil)  return nil;
	
	// N.b.: the Cocoa API for this lives in NSWorkspace, which is in AppKit.
	return CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)uti, kUTTagClassFilenameExtension));
}


static BOOL IsPrintableMacRoman(unsigned char c)
{
	// Tab, CR, LF and NBSP deliberately excluded, along with various printing glyphs not likely to occur in FCCs.
	if (c < 32)  return NO;
	if (c == 127)  return NO;
	if (c >= 160 && c <= 173)  return NO;
	if (c >= 194 && c <= 202)  return NO;
	if (c >= 208 && c <= 215)  return NO;
	if (c >= 218 && c <= 221)  return NO;
	if (c >= 246)  return NO;
	
	return YES;
}


static NSString *StringFromResType(ResType type)
{
	unsigned char bytes[4] = { (type >> 24) & 0xFF, (type >> 16) & 0xFF, (type >> 8) & 0xFF, type & 0xFF };
	bool haveAlnum = false;
	bool isUnprintable = false;
	for (unsigned i = 0; i < 4; i++)
	{
		if (!IsPrintableMacRoman(bytes[i]))  isUnprintable = true;
		if (isalnum(bytes[i]))  haveAlnum = true;
	}
	if (!haveAlnum)  isUnprintable = true;
	
	if (isUnprintable)
	{
		return JATExpand(@"{type|HEX}", type);
	}
	else
	{
		return JATExpand(@"'{0}'", [[NSString alloc] initWithBytes:bytes length:4 encoding:NSMacOSRomanStringEncoding]);
	}
}


static NSString *StringFromPascalString(ConstStr255Param pstring)
{
	return CFBridgingRelease(CFStringCreateWithPascalString(NULL, pstring, kCFStringEncodingMacRoman));
}
