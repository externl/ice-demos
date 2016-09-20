// **********************************************************************
//
// Copyright (c) 2003-2014 ZeroC, Inc. All rights reserved.
//
// This copy of Ice Touch is licensed to you under the terms described in the
// ICE_TOUCH_LICENSE file included in this distribution.
//
// **********************************************************************

#include <Ice/Ice.h>
#include <FileI.h>
#include <DirectoryI.h>

@implementation FileI

@synthesize myName;
@synthesize parent;
@synthesize ident;
@synthesize lines;

+(id) filei:(NSString *)name parent:(DirectoryI *)parent
{
    FileI *instance = [[FileI alloc] init];
#if defined(__clang__) && !__has_feature(objc_arc)
    [instance autorelease];
#endif
    if(instance == nil)
    {
        return nil;
    }
    instance.myName = name;
    instance.parent = parent;
    instance.ident = [ICEIdentity identity:[ICEUtil generateUUID] category:nil];
    return instance;
}

-(NSString *) name:(ICECurrent *)current
{
    return myName;
}

-(NSArray *) read:(ICECurrent *)current
{
    return lines;
}

-(void) write:(NSMutableArray *)text current:(ICECurrent *)current
{
    self.lines = text;
}

-(void) activate:(id<ICEObjectAdapter>)a
{
    id<FSNodePrx> thisNode = [FSNodePrx uncheckedCast:[a add:self identity:ident]];
    [parent addChild:thisNode];
}

#if defined(__clang__) && !__has_feature(objc_arc)
-(void) dealloc
{
    [myName release];
    [parent release];
    [ident release];
    [lines release];
    [super dealloc];
}
#endif
@end
