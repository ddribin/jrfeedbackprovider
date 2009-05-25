/*******************************************************************************
    JRFeedbackController.m
        Copyright (c) 2008-2009 Jonathan 'Wolf' Rentzsch: <http://rentzsch.com>
        Some rights reserved: <http://opensource.org/licenses/mit-license.php>

    ***************************************************************************/

#import "JRFeedbackController.h"
#import <AddressBook/AddressBook.h>
#import "NSURLRequest+postForm.h"
#import <SystemConfiguration/SCNetwork.h>

JRFeedbackController *gFeedbackController = nil;

NSString *JRFeedbackType[JRFeedbackController_SectionCount] = {
    @"BUG", // JRFeedbackController_BugReport
    @"FEATURE", // JRFeedbackController_FeatureRequest
    @"SUPPORT" // JRFeedbackController_SupportRequest
};

@interface JRFeedbackController ()
+ (NSURL*)postURL;
@end

@implementation JRFeedbackController

+ (void)showFeedback {
    [self showFeedbackWithBugDetails:nil];
}

+ (void)showFeedbackWithBugDetails:(NSString *)details {
    SCNetworkConnectionFlags reachabilityFlags;
    Boolean reachabilityResult = SCNetworkCheckReachabilityByName([[[JRFeedbackController postURL] host] UTF8String], &reachabilityFlags);
    
    //NSLog(@"reachabilityFlags: %lx", reachabilityFlags);
    BOOL showFeedbackWindow = reachabilityResult
        && (reachabilityFlags & kSCNetworkFlagsReachable)
        && !(reachabilityFlags & kSCNetworkFlagsConnectionRequired)
        && !(reachabilityFlags & kSCNetworkFlagsConnectionAutomatic)
        && !(reachabilityFlags & kSCNetworkFlagsInterventionRequired);
    
    if (!showFeedbackWindow) {
        int alertResult = [[NSAlert alertWithMessageText:@"Feedback Host Not Reachable"
                                           defaultButton:@"Proceed Anyway"
                                         alternateButton:@"Cancel"
                                             otherButton:nil
                               informativeTextWithFormat:@"You may not be able to send feedback because %@ isn't reachable.\n\nPlease ensure you have a network connection before proceeding.\n", [[JRFeedbackController postURL] host]
                            ] runModal];
        if (NSAlertDefaultReturn == alertResult) {
            showFeedbackWindow = YES;
        }
    }
    
    if (showFeedbackWindow) {
        if (!gFeedbackController) {
            gFeedbackController = [[JRFeedbackController alloc] init];
        }
        [gFeedbackController showWindow:self];
        
        // There is an assumption here that bug report is the first and default view of the window.
        if (details) {
            [gFeedbackController setTextViewStringTo:details];
        }
    }
}

- (id)init {
    self = [super initWithWindowNibName:@"JRFeedbackProvider"];
    if (self) {
        //[self window];
        includeContactInfo = YES;
    }
    return self;
}

- (void)windowDidLoad {
    NSString* title = [NSString stringWithFormat:@"%@ Feedback", [[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:(NSString*)kCFBundleNameKey]];
    [[self window] setTitle:title];
    
    NSTextStorage *text = [textView textStorage];
    
    NSString *seperator = @"\n\n--\n\n";
    
    NSRange seperatorRange = [[text string] rangeOfString:seperator];
    sectionStrings[JRFeedbackController_BugReport] = [[text attributedSubstringFromRange:NSMakeRange(0, seperatorRange.location)] retain];
    [text deleteCharactersInRange:NSMakeRange(0, seperatorRange.location + [seperator length])];
    //NSLog(@"bugReport: <%@>", [sectionStrings[JRFeedbackController_BugReport] string]);
    
    seperatorRange = [[text string] rangeOfString:seperator];
    sectionStrings[JRFeedbackController_FeatureRequest] = [[text attributedSubstringFromRange:NSMakeRange(0, seperatorRange.location)] retain];
    [text deleteCharactersInRange:NSMakeRange(0, seperatorRange.location + [seperator length])];
    //NSLog(@"featureRequest: <%@>", [sectionStrings[JRFeedbackController_FeatureRequest] string]);
    
    sectionStrings[JRFeedbackController_SupportRequest] = [[text attributedSubstringFromRange:NSMakeRange(0, [text length])] retain];
    //NSLog(@"supportRequest: <%@>", [sectionStrings[JRFeedbackController_SupportRequest] string]);
    
    [text setAttributedString:sectionStrings[JRFeedbackController_BugReport]];
    [textView moveToBeginningOfDocument:self];
    [textView moveDown:self];
    
    ABPerson *me = [[ABAddressBook sharedAddressBook] me];
    if (me) {
        [nameTextField setStringValue:[NSString stringWithFormat:@"%@ %@", [me valueForProperty:kABFirstNameProperty], [me valueForProperty:kABLastNameProperty]]];
        ABMutableMultiValue *emailAddresses = [me valueForProperty:kABEmailProperty];
        unsigned addyIndex = 0, addyCount = [emailAddresses count];
        for (; addyIndex < addyCount; addyIndex++) {
            [emailAddressComboBox addItemWithObjectValue:[emailAddresses valueAtIndex:addyIndex]];
        }
        [emailAddressComboBox selectItemAtIndex:0];
    }
}

- (BOOL)includeContactInfo {
    return includeContactInfo;
}
- (void)setIncludeContactInfo:(BOOL)flag {
    includeContactInfo = flag;
}

- (IBAction)switchSectionAction:(NSSegmentedControl*)sender {
    [sectionStrings[currentSection] release];
    sectionStrings[currentSection] = [[textView textStorage] copy];
    
    currentSection = [sender selectedSegment];
    [[textView textStorage] setAttributedString:sectionStrings[currentSection]];
    [textView moveToBeginningOfDocument:self];
    [textView moveDown:self];
    
    if (JRFeedbackController_SupportRequest == currentSection) {
        [self setIncludeContactInfo:YES];
    }
}

- (IBAction)submitAction:(id)sender {
    [sectionStrings[currentSection] release];
    sectionStrings[currentSection] = [[textView textStorage] copy];
    [textView setEditable:NO];
    
    [progress startAnimation:self];
    
    // if they checked not to include hardware, don't scan. Post right away.
    if ([includeHardwareDetailsCheckbox intValue] == 1) {
        [NSThread detachNewThreadSelector:@selector(system_profilerThread:)
                                 toTarget:self
                               withObject:nil];
    } else {
        [self postFeedback:@"<systemProfile suppressed>"];
    }
}

- (void)system_profilerThread:(id)ignored {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSString *systemProfile = nil;
    {
        NSPipe *inputPipe = [NSPipe pipe];
        NSPipe *outputPipe = [NSPipe pipe];
        
        NSTask *scriptTask = [[[NSTask alloc] init] autorelease];
        [scriptTask setLaunchPath:@"/usr/sbin/system_profiler"];
        [scriptTask setArguments:[NSArray arrayWithObjects:@"-detailLevel", @"mini", nil]];
        [scriptTask setStandardOutput:outputPipe];
        [scriptTask launch];
        
        [[inputPipe fileHandleForWriting] closeFile];
        systemProfile = [[[NSString alloc] initWithData:[[outputPipe fileHandleForReading] readDataToEndOfFile]
                                               encoding:NSUTF8StringEncoding] autorelease];
    }
    [self performSelectorOnMainThread:@selector(postFeedback:)
                           withObject:systemProfile
                        waitUntilDone:NO];
    [pool drain];
}

- (void)postFeedback:(NSString*)systemProfile {
    
    NSMutableDictionary *form = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                 JRFeedbackType[currentSection], @"feedbackType",
                                 [sectionStrings[currentSection] string], @"feedback",
                                 [[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleName"], @"appName",
                                 [[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleIdentifier"], @"bundleID",
                                 [[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleVersion"], @"version",
                                 nil];
    if (systemProfile) {
        [form setObject:systemProfile forKey:@"systemProfile"];
    }
    if ([self includeContactInfo]) {
        if ([[emailAddressComboBox stringValue] length]) {
            [form setObject:[emailAddressComboBox stringValue] forKey:@"email"];
        }
        if ([[nameTextField stringValue] length]) {
            [form setObject:[nameTextField stringValue] forKey:@"name"];
        }
    }
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[JRFeedbackController postURL] postForm:form];
    [NSURLConnection connectionWithRequest:request delegate:self];
}

- (void)closeFeedback {
    if (gFeedbackController) {
        assert(gFeedbackController == self);
        [[gFeedbackController window] orderOut:self];
        [gFeedbackController release];
        gFeedbackController = nil;
    }
}

- (IBAction)cancelAction:(id)sender {
    [self closeFeedback];
}

- (void)connectionDidFinishLoading:(NSURLConnection*)connection {
    // TODO Drop Thank you sheet
    [self closeFeedback];
}

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError*)error {
    NSLog(@"-[JRFeedback connection:didFailWithError:%@]", error);
    [self closeFeedback];
}

- (void)windowWillClose:(NSNotification*)notification {
    [self closeFeedback];
}

- (void)setTextViewStringTo:(NSString *)details
{
    // TODO: doing this makes all the text bold, I'm not hip to the attr string stuff done in this class
    // so it's not easy for me to fix.
    [textView setString:details];
}

+ (NSURL*)postURL {
    NSString *postURLString = [[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"JRFeedbackURL"];
    if ([[NSUserDefaults standardUserDefaults] stringForKey:@"JRFeedbackURL"]) {
        postURLString = [[NSUserDefaults standardUserDefaults] stringForKey:@"JRFeedbackURL"];
    }
    NSAssert(postURLString, @"JRFeedbackURL not defined");
    return [NSURL URLWithString:postURLString];
}

@end
