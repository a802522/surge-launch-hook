// Surge 6.100.0 launch hook: make the app's own root selection land on the
// normal tab bar instead of SGUActivationViewController, and skip the
// one-time feature intro. Built as a plain arm64 iOS dylib.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

static void (*gOrigReload)(id, SEL);

static id safeValue(id obj, NSString *key) {
    @try {
        return [obj valueForKey:key];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static void forceTabs(id delegate) {
    if (!delegate) return;
    @try {
        UIWindow *win = safeValue(delegate, @"window");
        if (![win isKindOfClass:[UIWindow class]]) return;

        UIViewController *tabs = safeValue(delegate, @"tabBarController");
        if (![tabs isKindOfClass:[UIViewController class]]) {
            tabs = safeValue(delegate, @"rootViewController");
        }
        if (![tabs isKindOfClass:[UIViewController class]]) return;

        if (win.rootViewController != tabs) {
            win.rootViewController = tabs;
        }
        [win makeKeyAndVisible];
    } @catch (__unused NSException *e) {
    }
}

static void hookedReload(id self, SEL _cmd) {
    if (gOrigReload) gOrigReload(self, _cmd);
    forceTabs(self);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ forceTabs(self); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ forceTabs(self); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ forceTabs(self); });
}

static void noop0(id self, SEL _cmd) { (void)self; (void)_cmd; }
static void noop1(id self, SEL _cmd, id a) { (void)self; (void)_cmd; (void)a; }
static void noop2(id self, SEL _cmd, id a, BOOL b) { (void)self; (void)_cmd; (void)a; (void)b; }

static void install(void) {
    Class cls = objc_getClass("SGUAppDelegate");
    if (!cls) return;

    Method reload = class_getInstanceMethod(cls, sel_registerName("reloadRootViewController"));
    if (reload) {
        gOrigReload = (void (*)(id, SEL))method_getImplementation(reload);
        method_setImplementation(reload, (IMP)hookedReload);
    }

    // The binary patches already ret these two, but keep the dylib usable on a
    // clean IPA as well.
    Method a = class_getInstanceMethod(cls, sel_registerName("showPurchaseViewControllerAnimated:"));
    if (a) method_setImplementation(a, (IMP)noop1);

    Method b = class_getInstanceMethod(cls, sel_registerName("showPurchaseViewControllerForFeatures:animated:"));
    if (b) method_setImplementation(b, (IMP)noop2);

    // Mark the feature intro as seen; DylanIOS does the same in _SurgeProActivate.
    Class ud = objc_getClass("SGUUserDefaults");
    if (ud) {
        id defaults = ((id (*)(id, SEL))objc_msgSend)((id)ud, sel_registerName("sharedDefaults"));
        if (defaults) {
            @try {
                [defaults setValue:@6 forKey:@"featureIntroVersion"];
            } @catch (__unused NSException *e) {
            }
        }
    }
}

__attribute__((constructor))
static void surge_launch_hook_init(void) {
    install();
}
