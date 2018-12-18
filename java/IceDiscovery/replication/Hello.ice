// **********************************************************************
//
// Copyright (c) 2003-2018 ZeroC, Inc. All rights reserved.
//
// **********************************************************************

#pragma once

["java:package:com.zeroc.demos.IceDiscovery.replication"]
module Demo
{
    interface Hello
    {
        idempotent string getGreeting();
        void shutdown();
    }
}
