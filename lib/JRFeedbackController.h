/*******************************************************************************
    JRFeedbackController.h
        Copyright (c) 2008-2009 Jonathan 'Wolf' Rentzsch: <http://rentzsch.com>
        Some rights reserved: <http://opensource.org/licenses/mit-license.php>

    ***************************************************************************/

#import <Cocoa/Cocoa.h>

typedef enum {
    JRFeedbackController_BugReport,
    JRFeedbackController_FeatureRequest,
    JRFeedbackController_SupportRequest,
    JRFeedbackController_SectionCount
} JRFeedbackController_Section;

@interface JRFeedbackController : NSWindowController {
    IBOutlet NSTextView *textView;
    IBOutlet NSButton *includeHardwareDetailsCheckbox;
    IBOutlet NSTextField *nameTextField;
    IBOutlet NSComboBox *emailAddressComboBox;
    IBOutlet NSProgressIndicator *progress;
    IBOutlet NSSegmentedControl *segmentedControl;
    
    NSAttributedString *sectionStrings[JRFeedbackController_SectionCount];
    JRFeedbackController_Section currentSection;
    BOOL includeContactInfo;
}

+ (void)showFeedback;
+ (void)showFeedbackWithBugDetails:(NSString *)details;

- (BOOL)includeContactInfo;
- (void)setIncludeContactInfo:(BOOL)flag;

- (IBAction)switchSectionAction:(NSSegmentedControl*)sender;
- (IBAction)submitAction:(id)sender;
- (IBAction)cancelAction:(id)sender;
- (void)postFeedback:(NSString*)systemProfile;
- (void)setTextViewStringTo:(NSString *)details;

@end
