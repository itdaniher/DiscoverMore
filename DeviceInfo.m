classdef DeviceInfo < daq.DeviceInfo
    %daq.di.DeviceInfo Device Information for Digilent Devices
    %
    %   This class represents Digilent Devices
    %   This undocumented class may be removed in a future release.
    
    %   Copyright 2012-2013 The MathWorks, Inc.

    % Specializations of the daq.di.DeviceInfo class should call 
    % addSubsystem repeatedly to add a SubsystemInfo record to their 
    % device. 
    % Usage:
    % addSubsystem(SUBSYSTEM) adds an adaptor specific SubsystemInfo record
    % SUBSYSTEM to the device.    
    
    properties(Constant, Access = private)
        DiscoveryDeviceID = int32(2);
    end
    
    properties (Hidden)
        DeviceHandle
        
        % Flag to check if the device is already open
        IsOpen
        
    end
    
    properties (GetAccess = {?daq.di.Session}, SetAccess = private, Hidden)
        DeviceIndex
    end    
    
    methods (Hidden)
        function obj = DeviceInfo(vendor, device, deviceIndex)
            %Get the following parameters:
            %vendor, device, uniqueHWID. vendor and device are already passed
            %in

            % Get the serial number
            [status, serialNumber] = daq.di.dwf.FDwfEnumSN(int32(deviceIndex), blanks(32));
            daq.di.utility.throwOrWarnOnStatus(status);
            % Get the revision. We don't need the type for now as we only
            % support discovery
            [status, deviceType, devRev] = daq.di.dwf.FDwfEnumDeviceType(int32(deviceIndex), int32(2), int32(0));
            daq.di.utility.throwOrWarnOnStatus(status);
            
%             % Only Analog Discovery is presently supported.
            if (~isequal(deviceType, daq.di.DeviceInfo.DiscoveryDeviceID))
                throw(MException(message('daq:DeviceInfo:dispNotSupportedFootnote')))
            end
                    
%             assert(isequal(daq.di.DeviceInfo.DiscoveryDeviceID,deviceType));
            
            % Get whether the device is opened by another program or not.
            [status, ~] = daq.di.dwf.FDwfEnumDeviceIsOpened(deviceIndex, int32(0));
            daq.di.utility.throwOrWarnOnStatus(status);
            
            % Call the superclass constructor: the device ID is AD<devIdx+1>
            obj@daq.DeviceInfo(vendor,['AD' num2str(deviceIndex+1)], device, serialNumber);
            
            [status, devHandle] = daq.di.dwf.FDwfDeviceOpen(deviceIndex, int32(0));
            daq.di.utility.throwOrWarnOnStatus(status);
            openStat = true;
            
            obj.RecognizedDevice = true;
            obj.IsOpen = openStat;
            obj.Description = [obj.Vendor.FullName ' ' device ' Kit Rev. ' cast(int32('A')+devRev-1, 'char')];
            obj.DeviceIndex = deviceIndex;
            obj.DeviceHandle = devHandle;
            % Add analog-input subsystem with the device index
            obj.addSubsystem(daq.di.AnalogInputInfo(deviceIndex, devHandle))
            
            % Add analog-output subsystem; no device index required, by
            % Digilent, for initializing the this subsystem.
            obj.addSubsystem(daq.di.AnalogOutputInfo(devHandle))   
            
            %Close the device, we've gathered all the properties that
            %require device opening
            [status] = daq.di.dwf.FDwfDeviceClose(devHandle);
            daq.di.utility.throwOrWarnOnStatus(status);
            obj.IsOpen = false;
            
        end
        
        function [newChannel] = createChannel(obj,...
                session,...         % The daq.Session that this is to be added to
                subsystem,...       % A daq.internal.SubsystemType defining the type of the subsystem to create a channel for on the device
                channelID,...       % A string or numeric containing the ID of the channel to create
                measurementType,... % A string containing the specialized measurement to be used, such as 'Voltage'.
                varargin)           % Any additional parameters passed by the user, to be interpreted by the vendor implementation
            % createChannel is a factory to create channels of the correct
            % type for Digilent devices
            
            channelLocation = char(subsystem) ;
            
            %Core will only allow execution to reach here if the requested
            %subsystem has been implemented
            
            switch subsystem
                case {daq.internal.SubsystemType.AnalogInput,...
                      daq.internal.SubsystemType.AnalogOutput}  
                    session.checkIsValidChannelID(obj, channelID, subsystem);
                    newChannel = daq.di.([channelLocation measurementType 'Channel'])(session, obj, channelID);
            end
        end
    end
   
end