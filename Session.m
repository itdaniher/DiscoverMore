classdef (Hidden) Session < daq.Session
    % daq.di Digilent Session object for Digilent DAQ
    % It contains all the vendor specific code for accessing this hardware.
    
    % Copyright 2012-2013 The MathWorks, Inc.
    
    
    %% -- Public methods, properties, and events --
    
    
    %% Constants
    properties(Constant, GetAccess = private, Hidden)
        MaximumRateVariationPercentage = 1;
        % g914489: min rate must be larger than minimum rate for
        % synchronous input/output
        InitialRate = 10000; 
        APIConstant_InitialOffset = double(0);
        
        % g914489: minimum rate determined by subsystems present
        % Must send a minimum of a buffer's worth of data per second
        MinimumAnalogOutputRate = daq.di.internal.const.AnalogDiscovery.AnalogOutputBufferSize;
        % Minimum permissible rate for synchronous analog input/output
        MinimumSynchronousAnalogInputOutputRate = daq.di.internal.const.AnalogDiscovery.AnalogInputBufferSize;
        % Maximum permissible rate for synchronous analog input/output
        MaximumSynchronousAnalogInputOutputRate = 3e5;
        
        % HEURISTICS: Determined experimentally
        % These values are conservatively chosen and may need to be
        % revisited in future revisions.
        
        % This is the pause duration for the device acquisition to be
        % stable
        % Seconds required to establish that the device acquisition is a
        % stable/reasonable value. This is a experimentally determine
        % heuristic.
        
        PauseForStabilityDuration = 0.6;
        
        % Units (duration): seconds
        % These factors were determined by trial/error and the general
        % guideline to keep these intervals brief
        
        APIConstant_AITriggerLength = 0.01;
        
        % The trigger hold-off is an adjustable period of time during which
        % the acquisition will not trigger. This may be useful when
        % triggering off of burst waveforms.
        APIConstant_AITriggerHoldOff = 0.1008;       
     
    end
    
    %% Common API Constants
    properties(Constant, Hidden)
         APIConstant_Success = int32(1);        
    end
    
    % These may become accessible at some point
    properties (SetAccess = private, Hidden)
        % Determines how data will be acquired into the ADC buffer.
        AcquisitionMode 
        % Determines how data will be provided to the DAC buffer.
        GenerationMode
                
        % Triggers cause subsystems to start running.
        % TriggerSources indicate where these triggers come from               
        AnalogInputTriggerSource
        AnalogOutputTriggerSource

        % An analog input may be triggered if the trigger is less-than, 
        % equal-to or more-than a certain duration.
        AnalogInputTriggerLengthCondition;
        
        % Determines how samples are processed prior to being stored in the
        % internal ADC buffer
        AcquisitionFilter
       
    end
    
    % Hidden private properties
    % These will almost certainly remain hidden/private
    properties(Access = private, Hidden)
        % Input data available merge buffer
        DataAvailableBuffer;
        
        % TriggerTime of first trigger in a multi trigger acquisition
        InitialTriggerTime;
        
        % Total number of scans acquired - used to compute time stamps
        % information
        TotalScansAcquired;
        
        % Flag to indicate whether session has reserved hardware through
        % prepare. This flag is needed to allow for multiple sessions only
        % releasing the hardware that they've reserved, as the vendor API
        % is session agnostic
        IsHardwareReserved = false;
        
        %Device Handles acquired by the session
        DeviceHandles
        
        % Internal property that suppresses set.* functions during
        % initialization
        InitializationInProgress        
        
        AnalogInputRecord
        AnalogOutputRecord 
        
        AnalogIOMasterSwitchState         
    end    
    
    properties (SetAccess = private, Hidden)
        ChannelIndex
        OutputQueue
        OutputQueueLength
    end
    
    %% -- Protected and private members of the class --
    % Non-public or hidden constructor
    methods(Hidden)
        function obj = Session(vendor)
            % Assume an initial rate of 1000 scans/second
            obj@daq.Session(vendor, daq.di.Session.InitialRate);
            
            obj.TriggerReceived = false;
            obj.TriggerTime = [];
            obj.IsHardwareReserved = false;
            
            % Defaults valid for single-scan outputs
            obj.GenerationMode = daq.di.internal.enum.GenerationMode.DC;
            obj.AnalogOutputTriggerSource = daq.di.internal.enum.TrigSrc.None;
            
            % Defaults valid for input-only mode
            obj.AcquisitionMode = daq.di.internal.enum.AcquisitionMode.ScanScreen;
            obj.AcquisitionFilter = daq.di.internal.enum.AcquisitionFilter.Decimate;
            
            obj.AnalogInputRecord = daq.di.internal.ChannelRecord();
            obj.AnalogOutputRecord = daq.di.internal.ChannelRecord();
            
            obj.DeviceHandles = int32([]);
            obj.OutputQueue = [];
            obj.OutputQueueLength = 0;
            
            % Power-supplies: disabled to start
            obj.AnalogIOMasterSwitchState = int32(0); 
            
        end
        
        function delete(obj)
            % Ensure all the devices are released
%             [status] = daq.di.dwf.FDwfDeviceCloseAll();
%             daq.di.utility.throwOrWarnOnStatus(status);
            
            % g915831: Must not use FDwfDeviceCloseAll() to close handles
            % for a single session, as this invalidates other sessions.
            
            obj.closeDevicesInSession;
            
        end
    end
    
    % Hidden methods, which are typically used as friend methods
    methods(Hidden)
        function updateRateLimit(obj)
            % updateRateLimit Adjust the RateLimit to reflect changes in
            % configuration.  Needs to be available to channels in case
            % property updates will effect the rate limit.
            
            % If there are no channels, set obj.RateLimitInfo to empty
            if isempty(obj.Channels)
                obj.RateLimitInfo = daq.internal.ParameterLimit.empty;
                return
            end
            
            [numAnalogOutputChannels, ~, ~] = obj.lookupAnalogOutputChannels();            
            [numAnalogInputChannels, ~, ~] =  obj.lookupAnalogInputChannels();
            
            % This is where we would find the common rate for multiple
            % device-types and set it for the session. 
            % Since we are presently only support Analog-Discovery, 
            % simply get the max rate and set it.
                devices = daq.getDevices;
                digilentDevices = devices.locate('digilent');
                for i = 1:numel(digilentDevices)
                    aiSubsystem = digilentDevices(i).getSubsystem(daq.internal.SubsystemType.AnalogInput);
                    aoSubsystem = digilentDevices(i).getSubsystem(daq.internal.SubsystemType.AnalogOutput);
                
                    aiRateLimits = aiSubsystem.RateLimitInfo;
                    aoRateLimits = aoSubsystem.RateLimitInfo;
                    
                    % Min rate = largest possible minimum
                    % Max rate = smallest possible maximum

                    minRate = max(aiRateLimits.Min, aoRateLimits.Min);
                    maxRate = min(aiRateLimits.Max, aoRateLimits.Max);
                    
                    % g910619: show appropriate device limitations
                    % Given the present driver limitations, the rate limit
                    % for:
                    %       - AI or AO _only_ is around 1 MHz.
                    %       - AI and AO together is about 300 KHz
                    % Faster rates are possible, but warnings are more
                    % likely to be generated.
                    % g914489: minimum rates determined by subsystems
                    % present.
                    
                    % If only analog input channels are present, do
                    % nothing.
                    % If only analog output channels are present, set a
                    % minimum rate.
                    % If both analog input/output channels are present,
                    % set both a minimum and a maximum rate.
                    if (numAnalogOutputChannels > 0)
                        oldMinRate = minRate;
                        if (numAnalogInputChannels > 0)
                            minRate = max(oldMinRate,...
                                          daq.di.Session.MinimumSynchronousAnalogInputOutputRate);
                            oldMaxRate = maxRate;
                            maxRate = min(oldMaxRate,...
                                          daq.di.Session.MaximumSynchronousAnalogInputOutputRate);
                        else
                            minRate = max(oldMinRate,...
                                          daq.di.Session.MinimumAnalogOutputRate);
                        end
                    end
                    obj.RateLimitInfo = daq.internal.ParameterLimit(minRate, maxRate);
                end
        end

        function checkIsValidChannelID(obj, deviceInfo, id, subsystem)
            % G722712: Check for invalid channel names
            if ~ismember(id, deviceInfo.getSubsystem(subsystem).ChannelNames)
                obj.throwUnknownChannelIDError(...
                    deviceInfo,...
                    num2str(id),...
                    deviceInfo.getSubsystem(subsystem).ChannelNames)
            end
        end
        
       
        % Hidden public sealed methods, which are typically used as friend
        % methods
        
        function digilentLocalizedError(obj, id, varargin)
            % If the catalog is loaded for Digilent, or a normal ID is
            % passed then dispatch the correct error. Otherwise, throw a
            % generic one.
            %Check to see if 'digilent' is included in ID
            nonDigilentID = isempty(strfind(id,'digilent'));
            if (obj.Vendor.IsCatalogLoaded || nonDigilentID)
                obj.localizedError(id, varargin{:});
            else
                %Throw generic error because ID passed in because either the
                %ID was not provided or the digilent catalog wasn't loaded
                
                obj.localizedError('daq:general:notImplemented');
            end
            
        end
        
    end
    
    % Power-Supply access functions. These should be considered
    % undocumented and unsupported for future revisions
    methods(Hidden)
        function setPowerSupply(obj, powerSupplyType, powerSupplyState)
            
            % We need at least one of these conditions to be true:
            % A device-handle is available or channels are present in the
            % session.
            
            availableHandle = obj.getAvailableDeviceHandle;
            
            if isempty(availableHandle)
                % If we have no handle, check for available channels
                if ~isempty(obj.Channels)
                    % If we have channels, we can call prepare the device
                    % (obtain a device handle)
                    prepareHookIfUnreserved(obj);
                    availableHandle = obj.getAvailableDeviceHandle;
                else
                    obj.localizedError('daq:Session:noChannels');
                end
            end
            
            % We should now have an available device handle
            disabled = int32(0);
            enabled = int32(1);
            supplyActiveState = disabled;
            
            % Determine whether to enable or disable the supply
            switch lower(powerSupplyState)
                case 'off'
                    supplyActiveState = disabled;
                case 'on'
                    supplyActiveState = enabled;
                otherwise
                    warning('Please enter ''on'', or ''off''.');
            end
            
            % Determine which supply to enable/disable
            switch lower(powerSupplyType)
                case {'pos', 'positive'}
                    obj.digilentSetAnalogIOPositiveSupply(availableHandle, supplyActiveState);
                case {'neg', 'negative'}
                    obj.digilentSetAnalogIONegativeSupply(availableHandle, supplyActiveState);
                otherwise
                    warning('Please enter ''pos/positive'', or ''neg/negative''');
            end
        end
            
    end
    
    % Private properties
    properties (Access = private)
        % A bool indicating if trigger has been received. Keeping this for
        % now
        TriggerReceived
        
        % The initial trigger time captured from first call to
        % handleProcessAcquiredData
        TriggerTime;
        
    end
    
    
    % Superclass methods this class implements
    methods (Sealed, Access = protected)

        % createChannelImpl is implemented by the vendor to validate that
        % the requested channel can be created, and to create and return an
        % object of type daq.Channel conforming to the parameters passed.
        % All parameters will be pre-validated and will always be passed in
        % (other than the varargins)
        %
        %         function newChannel = createChannelImpl(obj,...
        %                 subsystem,...       % A daq.internal.SubsystemType defining the type of the subsystem to create a channel for on the device
        %                 isGroup,...         % A flag indicating if multiple channels should be grouped together
        %                 deviceInfo,...      % A daq.DeviceInfo object of the device that the channel exists on
        %                 channelID,...       % A cell array of strings or numeric vector containing the IDs of the channels to create
        %                 measurementType,... % A string containing the specialized measurement to be used, such as 'Voltage'.
        %                 varargin)           % Any additional parameters passed by the user, to be interpreted by the vendor implementation
        
        function newChannel = createChannelImpl(varargin)

            
            %There was a change to createChannelImpl between 12a and
            %12b. Check version.
            matlabInfo = ver('MATLAB');
            obj = varargin{1};
            if strcmpi(matlabInfo.Release, '(R2012a)')
                %12a signature
                subsystem = varargin{2};
                deviceInfo = varargin{3};
                channelID = varargin{4};
                measurementType = varargin{5};
                %                   remainingArgs = varargin(6:end);
                if isnumeric(channelID)
                    channelID= num2cell(channelID);
                end
            else
                %12b and beyond signature
                subsystem = varargin{2};
                deviceInfo = varargin{4};
                channelID = varargin{5};
                measurementType = varargin{6};
                %                    remainingArgs = varargin(7:end);
            end            
            
            
            newChannel = daq.Channel.empty();
            
            if (nargin > 6)
                obj.localizedError('MATLAB:maxrhs');
            end
            
            % The channel IDs are in a cell array. Check the array contents
            % for numerics: if found, convert them to strings
            if isnumeric(cell2mat(channelID))
                channelID = cellstr(cellfun(@num2str, channelID(:), 'uniformoutput', false));
            end
            
            % Get the subsystem name without any spaces
            subsysName = subsystem.getFullName;
            subsysName = subsysName(subsysName ~= ' ');
            
            for iChannel = 1:numel(channelID)
                id = channelID{iChannel};
                for chanIdx = 1:numel(obj.Channels)
                    theChannel = obj.Channels(chanIdx);
                    
                    % g910600: prevent adding channels from multiple
                    % devices until such support is comprehensive 
                    % (background operations are not presently supported).
                    % Verify that deviceInfo.ID of the new channel matches
                    % those of all existing channels
                    if ~strcmp(deviceInfo.ID, theChannel.Device.ID)
                        obj.digilentLocalizedError('digilent:discovery:channelsOnSeparateDevices');
                    end
                    
                    % Checking for subsystem is required for IDs
                    % such as '0', '1', etc. that do not intrinsically
                    % specify the subsystem.
                    if strcmp(theChannel.ID, id) &&...
                       strcmp(theChannel.Device.ID, deviceInfo.ID) &&...
                       strcmpi(theChannel.getSubsystem.SubsystemType, subsysName)
                            obj.digilentLocalizedError('digilent:discovery:sameChannelTwice',num2str(id))
                    end
                end
            end
            
            try
                for iChannel = 1:numel(channelID)
                    id = channelID{iChannel};
                    
                    % Delegate to the device channel factory method
                    newChannel(end + 1) = deviceInfo.createChannel(obj,...
                        subsystem,...               % A daq.internal.SubsystemType defining the type of the subsystem to create a channel for on the device
                        id,...                      % A string or integer containing the ID of the channel to create
                        measurementType,...         % A string containing the specialized measurement to be used, such as 'Voltage'.
                        varargin);                  %#ok<AGROW> % Any additional parameters passed by the user, to be interpreted by the vendor implementation
                    
                    % Add the new channel to the appropriate record
                    % Flush queue as necessary
                    % Must add 1 for each channel added because Channels
                    % are only updated upon return from createChannelImpl.
                    % g910539: must update by 'iChannel' and not by 1.
                    channelIndex = iChannel + numel(obj.Channels);
                    switch subsystem
                        case daq.internal.SubsystemType.AnalogInput
                            obj.AnalogInputRecord.addChannel(channelIndex);
                        case daq.internal.SubsystemType.AnalogOutput
                            obj.AnalogOutputRecord.addChannel(channelIndex);
                            obj.flushOutputDataImpl();
                        otherwise
                            % Left blank (if the subsystem isn't available,
                            % it should be caught well before this).
                    end                    
                end
            catch e
                rethrow(e)                
            end
        end
        
        % If this index exists in one of the channelRecords, remove it.
        % Also, if the index exists in any of the records, all indices
        % that exceed it must be reduced by 1 ('shift')
        function removeChannelHook(obj, index)
            obj.AnalogInputRecord.removeChannelAndShiftIndex(index);
            obj.AnalogOutputRecord.removeChannelAndShiftIndex(index);
            % Additional channel records can be added, as necessary
        end

        function startHardwareImpl(obj)
            obj.TotalScansAcquired = 0;
            obj.InitialTriggerTime = [];
            obj.DataAvailableBuffer = {};
            % Since background and foreground both call startHardware,
            % ensure only foreground is supported
            callStack = dbstack; %Get the callstack
            % Next, check the name field of each struct in the struct array
            % for startBackground
            if any(cell2mat(arrayfun(@(x) strfind(x.name, 'startBackground'), callStack, 'uniformoutput', false)))
                 obj.digilentLocalizedError('daq:general:unsupported', 'startBackground', 'daq.di.Session');
            end
           
            
            obj.startHardwareBetweenTriggersImpl();
        end

        % start the hardware between multiple triggers.
        function startHardwareBetweenTriggersImpl(obj)
           
            % Determine number of channels in each sub-system
            numAnalogInputChannels = obj.AnalogInputRecord.Count;
            numAnalogOutputChannels = obj.AnalogOutputRecord.Count;

            prepareHookIfUnreserved(obj);
            
            % Assumptions: we have at least one valid channel (AO or AI) and
            % it has been prepared

            if numAnalogInputChannels > 0
                % If we also have output channels, then we are in
                % Synchronized mode
                if numAnalogOutputChannels > 0
                    activeSubsystem = daq.di.internal.enum.ActiveSubsystems.AnalogSynchronized;
                    defaultState = 'NeedOutputDataAndPrepared';
                else
                    activeSubsystem = daq.di.internal.enum.ActiveSubsystems.AnalogInputOnly;
                    defaultState = 'ReadyToStartAndPrepared';
                end
                % If we don't have analog inputs, we must therefore have
                % analog outputs (changes once new subsystems are
                % available)
            else
                activeSubsystem = daq.di.internal.enum.ActiveSubsystems.AnalogOutputOnly;
                defaultState = 'NeedOutputDataAndPrepared';
            end

            % Cleanup: Put the session back in the correct state if a
            % control-c is detected
            
            normalCompletionFlag = false;
            
            c = onCleanup(@()detectTerminateRequest(obj,normalCompletionFlag, defaultState));            

            %Set the trigger time
            if isempty(obj.TriggerTime)
                obj.TriggerTime = now;
            end             
            
            switch (activeSubsystem)
                case daq.di.internal.enum.ActiveSubsystems.AnalogInputOnly
                    obj.startHardwareBetweenTriggersAI;
                case daq.di.internal.enum.ActiveSubsystems.AnalogOutputOnly
                    obj.startHardwareBetweenTriggersAO;
                    obj.flushOutputDataImpl();                   
                case daq.di.internal.enum.ActiveSubsystems.AnalogSynchronized
                    obj.startHardwareBetweenTriggersSyncAnalog;
                    obj.flushOutputDataImpl();
                otherwise
                    % Left Blank
            end
            
            % See g909388: explicitly checking for a termination request
            % should be handled by daq.Session, not vendor implementations.
            function detectTerminateRequest(obj, normalCompletionFlag, defaultState)
                
                if ~normalCompletionFlag
                    obj.changeState(defaultState);
                    obj.processHardwareStop();
                end
            end
        end
        
        
        % stopImpl is implemented by the vendor to request a hardware stop.
        % It is expected that the vendor will call processHardwareStop()
        % when the stop actually occurs.
        %
        % It is OK to call processHardwareStop() from within stopImpl, or
        % at a later time if the stop requires an asynchronous action off
        % the MATLAB thread (which it usually does)
        function stopImpl(obj)
            % All operations supported are presently synchronous. As
            % such, there is no meaningful way for a user to "stop" an
            % operation that has already started except to wait for it to
            % complete. 
            % 
            % This functionality will be supported in tandem with
            % asynchronous operations
            % 
            %
            obj.digilentLocalizedError('daq:general:unsupported', 'stop', 'daq.di.Session');
        end
        
        % Handle data to be queued to the hardware. All parameters will be
        % pre-validated and will always be passed in.
        function queueOutputDataImpl(obj, dataToOutput)
            % dataToOutput is an MxN array of doubles where...
            % M is the number of scans, and...
            % N is the number of output channels
            
            % Append new data to queue as column-vectors
            % Note: we do not take steps to order the columns in 'Session'
            % channel-order during enqueing.
            obj.OutputQueue = cat(1, obj.OutputQueue, dataToOutput);
            obj.OutputQueueLength = length(obj.OutputQueue);
        end
        
        % configSampleClockTimingImpl is implemented by the vendor to
        % handle multiple calls to queue output data between starting
        % operation
        
        % configSampleClockTimingImpl is implemented by the vendor to
        % reconfigure sample clock timing if needed. This is needed to
        % handle changing number of scans queued between operations        
        function configSampleClockTimingImpl(~)
            % Not Implemented
            % 
        end
        
        % Delete any data previously queued for output by the hardware.
        function flushOutputDataImpl(obj)
            obj.OutputQueue = [];
            obj.OutputQueueLength = 0;
        end
        
        % resetCountersImpl is implemented by the vendor to reset counter
        % input channels
        function resetCountersImpl(~)
            % Not Implemented
            % No counter subsystems available
        end
        
        % Acquire a single scan of the input channels and return it.
        %
        % data: (1 x N) array of doubles where N is the number of input
        % channels
        function [data,triggerTime] = inputSingleScanImpl(obj)

            prepareHookIfUnreserved(obj);            
            
            [numAnalogInputChannels, sessionChIdx, sessionCh] = ...
                obj.lookupAnalogInputChannels();
            
            % Preallocate the data array
            data = zeros(1, numAnalogInputChannels);
            
            % Start of acquisition
            % The state-diagram for an acquisition is:
            % Ready => Config => Prefill => Armed => Triggered => Done
            
            for iChannel = 1:numAnalogInputChannels
                devHandle = sessionCh(iChannel).Device.DeviceHandle;
                % Don't reconfigure; Start analog-IN configuration
                % Transition out of the READY state
                [status] = daq.di.dwf.FDwfAnalogInConfigure(...
                                        devHandle, ...
                                        daq.di.internal.const.Digilent.DoNotReconfigure, ...
                                        daq.di.internal.const.Digilent.ChannelStart);                                    
                daq.di.utility.throwOrWarnOnStatus(status);

                % Before reading any data, we poll the current state
                % of the device until the device is ready to return data.
                % 
                % G910418 (Speed of inputSingleScan): we do not need to
                % wait until the TRIGGERED state for a reading (the ADC
                % value returned during the PREFILL state is valid).
                while (1)
                    % Ask the device to return its state WITHOUT reading
                    % data in.
                    [status, devStatus] = daq.di.dwf.FDwfAnalogInStatus(...
                                        devHandle, ...
                                        daq.di.internal.const.Digilent.DoNotReadData, ...
                                        char(0));
                    daq.di.utility.throwOrWarnOnStatus(status);
                    
                    sts = daq.di.internal.enum.InstrumentStatus(uint8(devStatus));
                    
                    % Continue if not in the CONFIG state
                    switch(sts)
                        case {...
                              daq.di.internal.enum.InstrumentStatus.Cfg
                             }
                            continue;
                        otherwise
                            break;
                    end
                end
                
                % The device is now in a state that permits us to ask for
                % data. 
                
                % Ask the device to return its state and ALSO to read data
                [status, ~] = daq.di.dwf.FDwfAnalogInStatus(...
                                        devHandle, ...
                                        daq.di.internal.const.Digilent.DoReadData, ...
                                        char(0));
                                    
                daq.di.utility.throwOrWarnOnStatus(status);

                digilentChannelIndex = obj.sessionChIndexToDigilentChIndex(sessionChIdx(iChannel));                
                
                % For a given digilent input channel, ask for a single sample
                % of data.
                [status, data(1, iChannel)] = daq.di.dwf.FDwfAnalogInStatusSample(...
                                        devHandle, ...
                                        digilentChannelIndex, ...
                                        double(0));
                                    
                daq.di.utility.throwOrWarnOnStatus(status);
                
                triggerTime = now;
            end
        end
        
        % Generate a single scan of the output channels. 
        % All parameters will be pre-validated and will always be passed in.
        %
        % dataToOutputCellArray: 
        % (1 x N) array of doubles where N is the number of input
        % channels
        function outputSingleScanImpl(obj, dataToOutputArray)   
            
            prepareHookIfUnreserved(obj);

            [numAnalogOutputChannels, sessionChIdx, sessionCh] = ...
                obj.lookupAnalogOutputChannels();

            % Multiple devices are not yet supported (in principle, code is
            % safe).
            
            digilentChannelIndex = ...
                obj.sessionChArrayToDigilentChArray(numAnalogOutputChannels, ...
                                                    sessionChIdx);
            
            for iChannel = 1:numAnalogOutputChannels
                deviceHandle = sessionCh(iChannel).Device.DeviceHandle;

                % Triggers are not required for a single output sample
                obj.digilentAnalogOutputSetTriggerSource( ...
                                        deviceHandle, ...
                                        digilentChannelIndex(iChannel), ...
                                        daq.di.internal.enum.TrigSrc.None);
                % Set the generation function to DC
                % In DC mode, the waveform outputs respond to a change in
                % device offset values (set below)
                obj.digilentSetGenerationMode(... 
                                        deviceHandle, ...
                                        digilentChannelIndex(iChannel), ...
                                        daq.di.internal.enum.GenerationMode.DC);
            end
            
            for iChannel = 1:numAnalogOutputChannels
                deviceHandle = sessionCh(iChannel).Device.DeviceHandle;
                offset = dataToOutputArray(iChannel);
                
                obj.digilentAnalogOutputSetOffset(...
                                    deviceHandle,...
                                    digilentChannelIndex(iChannel),... 
                                    offset);
            end
        end
        
        % Adjust the rate of a session to reflect hardware limitations, 
        % such as rate clock dividers. If the device is being prepared,
        % find/set the rate on the device. Otherwise set the rate on the
        % session object. 
        function actualRate = adjustNewRateHook(obj)
            % NEWRATE = adjustNewRateHook(REQUESTEDRATE) is called with the
            % double REQUESTEDRATE input-parameter. The function returns the
            % double NEWRATE, which may be adjusted to reflect hardware
            % limitations.
            %
            % adjustNewRateHook is called after RateLimit checks have been
            % done.  NEWRATE will be adjusted to fall within RateLimit.
            % Note that sessionPropertyBeingChangedHook will still be
            % called regarding the change to Rate after this.
            
            % No channels available
            if isempty(obj.Channels)
                actualRate = obj.Rate;
                return;
            end
            
            actualRates = zeros(1,numel(obj.Channels));            
            
            % FDwfAnalogOut/In Frequency Set/Get have different
            % signatures: these must be called separately
            
            % Analog-Inputs          
            
            [numAnalogInputChannels, sessionChIdx, sessionCh] = ...
                obj.lookupAnalogInputChannels();
           
            for iChannel = 1:numAnalogInputChannels
                
                if obj.IsHardwareReserved
                    % If the hardware is reserved, then the Rate setting is being
                    % done by prepareHook.
                    deviceHandle = sessionCh(iChannel).Device.DeviceHandle;
                    
                    [status] = daq.di.dwf.FDwfAnalogInFrequencySet(deviceHandle, obj.Rate);
                    daq.di.utility.throwOrWarnOnStatus(status);
                    
                    [status, rate] = daq.di.dwf.FDwfAnalogInFrequencyGet(deviceHandle, double(0));
                    daq.di.utility.throwOrWarnOnStatus(status);
                else
                    %Otherwise just set the rate
                    rate = obj.Rate;
                end
                
                % indexRate = sessionChIdx(iChannel);
                actualRates(sessionChIdx(iChannel)) = rate;
            end
                                
             % Analog-Outputs 
             
            [numAnalogOutputChannels, sessionChIdx, sessionCh] = ...
                obj.lookupAnalogOutputChannels();
            
            for iChannel = 1:numAnalogOutputChannels
                
                if obj.IsHardwareReserved
                    % If the hardware is reserved, then the Rate setting is being
                    % done by prepareHook.
                    deviceHandle = sessionCh(iChannel).Device.DeviceHandle;
                    channelIndex = obj.sessionChIndexToDigilentChIndex(sessionChIdx(iChannel));
                    
                    [status] = daq.di.dwf.FDwfAnalogOutFrequencySet(deviceHandle, channelIndex, obj.Rate);
                    daq.di.utility.throwOrWarnOnStatus(status);
                    
                    [status, rate] = daq.di.dwf.FDwfAnalogOutFrequencyGet(deviceHandle, channelIndex, double(0));
                    daq.di.utility.throwOrWarnOnStatus(status);
                else
                    %Otherwise just set the rate
                    rate = obj.Rate;
                end
                
                % indexRate = sessionChIdx(iChannel);
                actualRates(sessionChIdx(iChannel)) = rate;
            end             
                           

            if any(abs(actualRates - mean(actualRates)) * 100/mean(actualRates) > daq.di.Session.MaximumRateVariationPercentage)
                % The various tasks could arrive at slightly different
                % rates -- if any of them vary too much, issue a warning
                tmpBuf = sprintf('%f, ', sort(actualRates(:)));
                tmpBuf(end-1:end) = [];
                obj.localizedWarning('digilent:discovery:variationInRates',tmpBuf)
            end
            actualRate = max(actualRates);                                
              
        end
        
        % Adjust the RateLimitInfo of the session to reflect channel
        % adds/deletes
        function updateRateLimitInfoHook(obj)
            % updateRateLimitInfoHook() is called after channels are added
            % or removed from a session. The RateLimitInfo property must be
            % directly set if the setting is to be changed.
            %
            % Note that sessionPropertyBeingChangedHook will still be
            % called regarding the change to RateLimitInfo after this.
            
            % Determine number of subsystems present:
            % If num == 2 => upper-limit is upper-limitA
            % If num == 1 => upper-limit is upper-limitB
            
            
            obj.updateRateLimit();
        end
        
        % Setup in order to reduce the latency of impending
        % startHardwareImpl calls (preallocate hardware in advance of
        % call).
        function prepareHook(obj)
            %For all the channels, ensure the devices are open and set the
            %filter and offset for each channel. Next, set the rate on the
            %session.
            if ~obj.IsHardwareReserved
                %Open the devices
                deviceIndexArray = obj.getDeviceIndicesFromChannels();
                for arrayIndex = 1: numel(deviceIndexArray)
                    
                    try
                        %Init device handle
                        deviceHandle = int32(0);
                        [status, deviceHandle] = daq.di.dwf.FDwfDeviceOpen(int32(deviceIndexArray(arrayIndex)), deviceHandle);
                        daq.di.utility.throwOrWarnOnStatus(status);
                        % Keep a reference to the device handle in the
                        % appropriate device object
                        obj.assignHandleToDevice(deviceIndexArray(arrayIndex), deviceHandle);
                        obj.DeviceHandles(end+1) = int32(deviceHandle);
                    catch ex
                        
                        % If a device programming error is issued, then
                        % the device is already open. Issue an error.
                        % Otherwise rethrow the exception
                        if strfind(ex.message, 'Device programming failed')
                            obj.digilentLocalizedError('digilent:discovery:deviceOpenFailed')
                        end
                    end
                    
                    
                end
                
                % Success implies hardware reservation
                obj.IsHardwareReserved = true;
            end
            
            % 1) adjustNewRateHook 
            % 2) Setting range is an AI only function
            % 3) Filter set is an AI only function
            % 4) ChannelOffset applies to both channels
            % 5) Default modes should be set, but not more than once.
            
            % Adjusted using all subsystems' rate-information
            obj.adjustNewRateHook();

            % Prepare AnalogInput Subsystem
            
            [numAnalogInputChannels, sessionChIdx, sessionCh] = ...
                obj.lookupAnalogInputChannels();
           
            for iChannel = 1:numAnalogInputChannels
                sessionChannelIdx = sessionChIdx(iChannel);
                sessionChannel = sessionCh(iChannel);
                deviceHandle = sessionChannel.Device.DeviceHandle;
    
                % Get the channel index and the range. 
                % The offset is always set to 0
                
                digilentChannelIndex = obj.sessionChIndexToDigilentChIndex(sessionChannelIdx);
                selectedRange = sessionChannel.Range.Max-sessionChannel.Range.Min;
                
                % Set the filter, offset and range
                [status] = daq.di.dwf.FDwfAnalogInChannelRangeSet(deviceHandle, ...
                                                                  digilentChannelIndex, ...
                                                                  selectedRange);
                daq.di.utility.throwOrWarnOnStatus(status);
                
                obj.digilentAnalogInputSetOffset(deviceHandle, digilentChannelIndex, daq.di.Session.APIConstant_InitialOffset);
                daq.di.utility.throwOrWarnOnStatus(status);                

                % This pause needed to allow device to stabilize
                % acquisition
                pause(daq.di.Session.PauseForStabilityDuration);

            end
            
            % G927643: an outputSingleScan when no input-channels are
            % present should not result 'deviceHandle' being left
            % undefined.
            %
            % If we do not have any input channels, then we must have at
            % least one output channel (prepare cannot be called without
            % channels present).
            if (numAnalogInputChannels < 1)
                deviceHandle = obj.Channels(1).Device.DeviceHandle;
            end
            
            % POWER-SUPPLIES
            % Prepare AnalogIO Subsystem: enable power-supply function.
            
            % Use deviceHandle from previous subsystem
            obj.digilentEnableAnalogIOMasterSwitch(deviceHandle);
            obj.AnalogIOMasterSwitchState = int32(1);            
        end
        
        % Release resources allocated during prepareHook in order to reduce
        % latency associated with start.
        function releaseHook(obj)
            % Close all devices that the session has prepared
            if obj.IsHardwareReserved
                if ~isempty(obj.DeviceHandles)
                    numDeviceHandles = numel(obj.DeviceHandles);
                    for i = 1:numDeviceHandles
                        % POWER-SUPPLIES
                        % Release AnalogIO Subsystem: disable power-supply
                        % function
                        obj.digilentDisableAnalogIOMasterSwitch(obj.DeviceHandles(i));
                    end
                    obj.AnalogIOMasterSwitchState = int32(0);
                end
                
                % We've reserved the devices so close all of the open devices
                % and reset the reserved flag to false
%                 [status] = daq.di.dwf.FDwfDeviceCloseAll();
%                 daq.di.utility.throwOrWarnOnStatus(status);
                obj.closeDevicesInSession;
                obj.IsHardwareReserved = false;
            end
        end
        
        function sessionPropertyBeingChangedHook(obj,propertyName,~)
            % sessionPropertyBeingChangedHook React to change in session
            % property.
            %
            % Provides the vendor the opportunity to react to changes in
            % session properties.  Note that releaseHook() will be called
            % before this if needed.
            %
            % sessionPropertyBeingChangedHook(PROPERTYNAME,NEWVALUE) is
            % called before property changes occur.  The vendor
            % implementation may throw an error to prevent the change, or
            % update their corresponding hardware session, if appropriate.
            % PROPERTYNAME is the name of the property to change, and
            % NEWVALUE is the new value the property will have if this
            % function returns normally.
            %
            switch propertyName
                case {'IsContinuous', ...
                      'NotifyWhenDataAvailableExceeds', ...
                      'NotifyWhenScansQueuedBelow', ...
                      'IsNotifyWhenDataAvailableExceedsAuto', ...
                      'IsNotifyWhenScansQueuedBelowAuto', ....
                      'ExternalTriggerTimeout', ...
                      'TriggersPerRun'}
                    obj.digilentLocalizedError('digilent:discovery:propertyNotApplicable', propertyName);
            end
        end
        
        function [syncObjectClassName] = getSyncManagerObjectClassNameHook(obj) %#ok<MANU>
            % getSyncObjectClassNameHook Specify the name of the class that
            % implements the vendor-specific daq.Sync specialization.
            %
            % Provide the vendor with the opportunity to specify the name 
            % of the class to use upon instantiation of the Sync object.
            %
            % [syncObjectClassName] = getSyncObjectClassNameHook() is
            % called when the session is created.
            syncObjectClassName = 'daq.di.SyncManager';
        end
    end
    
    %Private helper functions
    methods  (Access = private)
        
        function closeDevicesInSession(obj)
            % Closes all devices in the current session
            % Clears list of DeviceHandles
            % Called by 'delete' and 'releaseHook'
            if ~isempty(obj.DeviceHandles)
                numDeviceHandles = numel(obj.DeviceHandles);
                for i = 1:numDeviceHandles
                    % Device handles are int32
                    [status] = daq.di.dwf.FDwfDeviceClose(obj.DeviceHandles(i));
                    daq.di.utility.throwOrWarnOnStatus(status);
                end
            end
            
            obj.DeviceHandles = int32([]);
        end        
        
        function deviceIndices = getDeviceIndicesFromChannels(obj)
            % Return the unique device indices of all the channels in the 
            % session. This is done to ensure that devices are prepared
            % only once.
            devices = [obj.Channels.Device];
            deviceIndices = unique([devices.DeviceIndex]);
        end
        
        function assignHandleToDevice(obj, deviceIndex, deviceHandle)
            % Assign to a device object its acquired handle.
            % Device channels can access this get the handle from
            % the device they are associated with
            
            %Go through the channels in the session, until the right device
            %is found
            for channelIndex = 1:numel(obj.Channels)
                
                if obj.Channels(channelIndex).Device.DeviceIndex == deviceIndex;
                    %If we've found the device whose handle we just got,
                    %assign it and return
                    obj.Channels(channelIndex).Device.DeviceHandle = deviceHandle;
                    return;
                end
            end
        end
           
        function availableHandle = getAvailableDeviceHandle(obj)
            availableHandle = [];
            % If we have device handles, then return one of them.
            % When support for multiple devices becomes available, this
            % function needs to be updated.
            if ~isempty(obj.DeviceHandles)
                availableHandle = obj.DeviceHandles(1);
            end            
        end
        
        % Note: Cannot start multiple devices this way! Will need
        % AsyncIO plugin to start different devices simultaneously
        function channelListHasUniqueDevice(obj, numchannels, sessionChannels)
            % Comparison in one step (use eq(length(unique), numchannels)
            % is only possible if we can access all IDs via indexing
            if (numchannels > 1)
                if ~strcmp(sessionChannels(1).Device.ID, sessionChannels(2).Device.ID)
                    obj.digilentLocalizedError('digilent:discovery:channelsOnSeparateDevices');
                end
            end
        end
        
        % Run prepareHook if the device has not already been prepared.
        function prepareHookIfUnreserved(obj)
            if ~obj.IsHardwareReserved
                obj.prepareHook();
                obj.IsHardwareReserved = true;
            else
                return % Do nothing
            end
        end
         %%  startHardwareTriggerImpl helper functions
        function normalCompletionFlag = startHardwareBetweenTriggersAI(obj)

            [numAnalogInputChannels, sessionChIdx, sessionCh] = ...
                obj.lookupAnalogInputChannels();
            
            % Note: Cannot start multiple devices this way! Will need
            % AsyncIO plugin to start different devices simultaneously
            
            % Ensure channels are from the same device or throw error
            obj.channelListHasUniqueDevice(numAnalogInputChannels, sessionCh);
            
            deviceHandle = sessionCh(1).Device.DeviceHandle;
            samplesToAcquire = obj.NumberOfScans;
            totalAcquired = zeros(samplesToAcquire, numAnalogInputChannels);     
                                         
            channelArray = obj.sessionChArrayToDigilentChArray(numAnalogInputChannels, sessionChIdx);                                       
                                       
            for i = 1:numAnalogInputChannels
                obj.digilentSetAcquisitionFilter(...
                    deviceHandle, channelArray(i), daq.di.internal.enum.AcquisitionFilter.Average);
            end
            
            obj.digilentSetAcquisitionMode(deviceHandle, ...
                                           daq.di.internal.enum.AcquisitionMode.ScanScreen);
            
            %MEX function that implements foreground acquisition
            [status] = mexFDwfForeground(...
                deviceHandle, ...                  handle to the device
                int32(numAnalogInputChannels), ... number of channels to acquire from
                int32(samplesToAcquire), ...       number of samples to acquire
                totalAcquired, ...                 zeroed out data buffer
                uint32(samplesToAcquire), ...      the size of the buffer
                int32(channelArray));            % array of channel indices

            daq.di.utility.throwOrWarnOnStatus(status);
            obj.processHardwareStop();
            
            
            period = 1/obj.Rate;
            startTime = 0;
            % numsamples in data returned is what user asked for, not the
            % length of padded waveform
            numSamples = double(obj.NumberOfScans);
            endTime = startTime + (numSamples - 1) * period;
            timestamps = (startTime:period:endTime)';
            
            % Cannot presently run processAcquiredData more than once: call
            % it on the entire inputWaveform in one call.
            obj.processAcquiredData(obj.TriggerTime, ...
                                    timestamps,...
                                    totalAcquired);
           
            % No need to change state explicitly: that's handled by the
            % state-machine
            normalCompletionFlag = true;            
        end
        
        function normalCompletionFlag = startHardwareBetweenTriggersAO(obj)   
            
            [numAnalogOutputChannels, sessionChIdx, sessionCh] = ...
                obj.lookupAnalogOutputChannels();
            
            % Generate an error message if channels belong to
            % different devices
            obj.channelListHasUniqueDevice(numAnalogOutputChannels, sessionCh);
            deviceHandle = sessionCh(1).Device.DeviceHandle;            

            % zero-pad, normalize, enforce session channel-order
            [outputWaveform, waveformLength, maxOut] = obj.formatWaveformOut(numAnalogOutputChannels, sessionChIdx);
                        
            % {0, 1}: Single Channel
            % -1: Synchronized output on multiple channels
            [channelIndex] = obj.digilentAnalogOutputChannelIndex(numAnalogOutputChannels, sessionChIdx);            
            
            switch channelIndex
                case {0,1}
                    obj.digilentEnableChannel(deviceHandle, channelIndex);
                    obj.digilentSetAmplitude(deviceHandle, channelIndex, maxOut(1));
                    obj.digilentAnalogOutputSetOffset(deviceHandle, channelIndex, 0);
                case daq.di.internal.const.Digilent.ChannelSynchronized % -1
                    for i = 1:numAnalogOutputChannels
                        obj.digilentEnableChannel(deviceHandle, i-1);
                        obj.digilentSetAmplitude(deviceHandle, i-1, maxOut(i));
                        obj.digilentAnalogOutputSetOffset(deviceHandle, i-1, 0);
                    end
            end

            % Repetition: single repetition / no repeat-trigger
            obj.digilentSetNumRepeats(deviceHandle, channelIndex, daq.di.internal.const.Digilent.RepeatNone);
            obj.digilentSetRepeatTrigger(deviceHandle, channelIndex, daq.di.internal.const.Digilent.RepeatTriggerDisable);
            
            % Set the duration for all analog-output channels
            frequency = obj.Rate;
            obj.digilentAnalogOutputSetFrequency(deviceHandle, channelIndex, frequency);
            
            duration = waveformLength/frequency;
            obj.digilentAnalogOutputSetDuration(deviceHandle, channelIndex, duration);   
            
            digilentChannelOutArray = obj.sessionChArrayToDigilentChArray(numAnalogOutputChannels, sessionChIdx);            

            % Triggers are not selected for this use-case
            obj.digilentAnalogOutputSetTriggerSource(deviceHandle, channelIndex, daq.di.internal.enum.TrigSrc.None);
            
            % Accommodate long waveforms
            % Use 'PLAY' mode to generate a single waveform with a
            % specified duration.
            % Do not use 'CUSTOM' mode, which is for generating repeated
            % waveforms.
            obj.digilentSetGenerationMode(deviceHandle, channelIndex, daq.di.internal.enum.GenerationMode.Play);
            
            % Parameters:
            % handle, channelIdx, OutputBuffer, outputParams, status)
            % OutputParams: 
            % [samplesToGenerate, samplesOutFreeMaximum,
            % minOutFreeThreshold, channelOutArray, channelOutCount]

            % FreeMinimum & FreeThreshold are heuristics that were
            % determined experimentally: they may need to be revisited in
            % future revision. They were chosen to minimize the number
            % of calls to the API in the MEX file. This may be related to
            % the performance of a given machine (testing is required and 
            % conservative values need to be selected that work across
            % machines of varying performance). 
            %
            % Recommendation/Observation: MANUALLY tune params to fit all
            % cases until a decent rule is found (that is, use explicit
            % integer-values as opposed to a formula).
            %
            % See below for description of Output buffer params.
            %
            % Assumption, in all cases: we completely fill our output
            % buffers one time (full/linear).  
            
            % Generated: samples output to device buffer
            % Remainder: samples remaining to be sent to device buffer
            % [--- Generated ---|--- Remainder ---]
            % samplesToGenerate = Generated + Remainder
            %   If      Remainder >= minOutFreeThreshold
            %   Then    Loop until samplesOutFreeMinimum samples available
            %           in the device-buffer
            %   Else    Loop until 1 sample is available in the
            %           device-buffer
            %  
            % Recommendations/Observations:
            % 1) Threshold should be reasonably large (1/8 to 1/4
            %    device-buffer size)
            % 2) Min free samples should be significantly smaller than
            %    the threshold.            
            
            setupParams = struct('samplesToGenerate', int32(waveformLength),...
                                 'samplesOutFreeMinimum', int32(32),...
                                 'minFreeThreshold', int32(512+1),...
                                 'channelArray', digilentChannelOutArray,...
                                 'channelCount', int32(numAnalogOutputChannels));

            % Do not pre-fill the buffer using AnalogOutDataSet 
            % (this is being done in the MEX-file).
            try                  
            [status, ~] = ...
                mexFDwfForegroundGen(deviceHandle,...
                                     channelIndex,...
                                     outputWaveform,...
                                     setupParams,...
                                     char(0));
            catch err %#ok<NASGU>
                obj.digilentLocalizedError('digilent:discovery:outputSamplesLostExcessive');
            end
                                 
            % If no error occurred as a result of calling the mex-file,
            % then update ScansOutputByHardware
            % See also: g910572
            obj.processOutputEvent(obj.OutputQueueLength);
            
            daq.di.utility.throwOrWarnOnStatus(status);                                     
            
            pause(daq.di.Session.PauseForStabilityDuration);
            obj.processHardwareStop();

            normalCompletionFlag = true;
        end
        
        function normalCompletionFlag = startHardwareBetweenTriggersSyncAnalog(obj)
            
            [numAnalogInputChannels, sessionInputChIdx, sessionInputCh] = ...
                obj.lookupAnalogInputChannels();  
            
            [numAnalogOutputChannels, sessionOutputChIdx, sessionOutputCh] = ...
                obj.lookupAnalogOutputChannels();
                     
            % Generate an error message if channels belong to
            % different devices
            obj.channelListHasUniqueDevice(numAnalogInputChannels, sessionInputCh);
            obj.channelListHasUniqueDevice(numAnalogOutputChannels, sessionOutputCh);
            
            %% Multiple Devices Not Supported
            deviceHandle = sessionOutputCh(1).Device.DeviceHandle;
            
            % zero-pad, normalize, enforce session channel-order
            [outputWaveform, waveformLength, maxOut] = obj.formatWaveformOut(numAnalogOutputChannels, sessionOutputChIdx);
            
            % {0, 1}: Single Channel
            % -1: Synchronized output on multiple channels
            [channelIndex] = obj.digilentAnalogOutputChannelIndex(numAnalogOutputChannels, sessionOutputChIdx);
            
            % First enable channels (permits use of synchronization
            switch channelIndex
                case {0,1}
                    obj.digilentEnableChannel(deviceHandle, channelIndex);
                    obj.digilentSetAmplitude(deviceHandle, channelIndex, maxOut(1));
                    obj.digilentAnalogOutputSetOffset(deviceHandle, channelIndex, 0);
                case daq.di.internal.const.Digilent.ChannelSynchronized % -1
                    for i = 1:numAnalogOutputChannels
                        obj.digilentEnableChannel(deviceHandle, i-1);
                        obj.digilentSetAmplitude(deviceHandle, i-1, maxOut(i));
                        obj.digilentAnalogOutputSetOffset(deviceHandle, i-1, 0);
                    end
            end
            
            % Repetition: single repetition / no repeat-trigger
            obj.digilentSetNumRepeats(deviceHandle, channelIndex, daq.di.internal.const.Digilent.RepeatNone);
            obj.digilentSetRepeatTrigger(deviceHandle, channelIndex, daq.di.internal.const.Digilent.RepeatTriggerDisable);          
            
            % Set the duration for all channels in the subsystem
            frequency = obj.Rate;
            obj.digilentAnalogOutputSetFrequency(deviceHandle, channelIndex, frequency);
            
            % Duration for AI and AO subsystems are not equal
            analogOutDuration = waveformLength/frequency; % obj.Rate;
            obj.digilentAnalogOutputSetDuration(deviceHandle, channelIndex, analogOutDuration);

            % Perform acquisition for a set duration
            obj.digilentSetAcquisitionMode(deviceHandle, daq.di.internal.enum.AcquisitionMode.Record);            
            
            % Add trigger conditions
            obj.digilentAnalogInputSetTriggerChannel(deviceHandle, daq.di.internal.const.Digilent.Channel1);
            obj.digilentAnalogInputSetTriggerFilter(deviceHandle, daq.di.internal.enum.AcquisitionFilter.Decimate);
            obj.digilentAnalogInputSetTriggerLength(deviceHandle, daq.di.Session.APIConstant_AITriggerLength);
            obj.digilentAnalogInputSetTriggerLengthCondition(deviceHandle, daq.di.internal.enum.TrigLen.Timeout);
            obj.digilentAnalogInputSetTriggerHoldOff(deviceHandle, daq.di.Session.APIConstant_AITriggerHoldOff);
            
            % Actual analog duration is: double(obj.NumberOfScans)/obj.Rate;
            % If we are only generating one output-buffer's worth of data,
            % then fetch one input-buffer's worth of data.
            % Otherwise, we need to pad the input-buffer to make certain
            % that we read all available input-points.
            analogOutputBufferSize = daq.di.internal.const.AnalogDiscovery.AnalogOutputBufferSize;
            analogInputBufferSize = daq.di.internal.const.AnalogDiscovery.AnalogInputBufferSize;
            % waveformLength = n*analogOutputBufferSize
            % Two cases: n = 1 and n > 1
            if (waveformLength == analogOutputBufferSize)
                analogInWaveformLength = analogInputBufferSize;
            else % waveformLength is n*analogOutBufferSize, 
                analogInWaveformLength = waveformLength + analogOutputBufferSize;
                % Observation: must ask for MORE than 2 input-buffer's
                % worth of data
                if (analogInWaveformLength <= 2*analogInputBufferSize)
                    analogInWaveformLength = 2*analogInputBufferSize+1;
                end
            end
            analogInDuration = analogInWaveformLength/frequency;
            obj.digilentAnalogInputSetDuration(deviceHandle, analogInDuration);
            
            % Analog-Output triggers when Analog-In starts
            % Analog-Input triggers when user runs startForeground
            % For hardware triggering, set AI Trigger Source to a supported
            % pin (e.g. Digital, External)
            obj.digilentAnalogOutputSetTriggerSource(deviceHandle, channelIndex, daq.di.internal.enum.TrigSrc.AnalogIn);
            obj.digilentAnalogInputSetTriggerSource(deviceHandle, daq.di.internal.enum.TrigSrc.None);
            
            % Accommodate long waveforms
            % Use 'PLAY' mode to generate a single waveform with a
            % specified duration.
            % Do not use 'CUSTOM' mode, which is for generating repeated
            % waveforms.
            obj.digilentSetGenerationMode(deviceHandle, channelIndex, daq.di.internal.enum.GenerationMode.Play);
            
            % Params (Out, In):
            % [numSamples, samplesFreeMinimum, minFreeThreshold, 
            % channelArray, channelCount]

            % FreeMinimum & FreeThreshold are heuristics that were
            % determined experimentally: they may need to be revisited in
            % future revision. They were chosen to minimize the number
            % of calls to the API in the MEX file. This may be related to
            % the performance of a given machine (testing is required and 
            % conservative values need to be selected that work across
            % machines of varying performance). 
            %
            % Recommendation/Observation: MANUALLY tune params to fit all
            % cases until a decent rule is found (that is, use explicit
            % integer-values as opposed to a formula).
            %
            % See below for descriptions of Input/Output buffer params.
            %
            % Assumption, in all cases: we completely fill our input/output
            % buffers one time (full/linear).  
            
            % Generated: samples output to device buffer
            % Remainder: samples remaining to be sent to device buffer
            % [--- Generated ---|--- Remainder ---]
            % samplesToGenerate = Generated + Remainder
            %   If      Remainder >= minOutFreeThreshold
            %   Then    Loop until samplesOutFreeMinimum samples available
            %           in the device-buffer
            %   Else    Loop until 1 sample is available in the
            %           device-buffer
            %  
            % Recommendations/Observations:
            % 1) Threshold should be reasonably large (1/8 to 1/4
            %    device-buffer size)
            % 2) Min free samples should be significantly smaller than
            %    the threshold.
            
            % Output Params            
            samplesToGenerate = int32(waveformLength);            
            samplesOutFreeMinimum = int32(1); % int32(32);
            minOutFreeThreshold = int32(512+1);
            digilentChannelOutArray = obj.sessionChArrayToDigilentChArray(numAnalogOutputChannels, sessionOutputChIdx);
            channelOutCount = int32(numAnalogOutputChannels);

            % Acquired: samples acquired from device buffer
            % Remainder: space remaining in buffer for acquired samples
            % [--- Acquired ---|--- Remainder ---]
            % samplesToAcquire = Acquired + Remainder
            %   If      Remainder >= minInFreeThreshold
            %   Then    Loop until samplesInAvailMinimum samples available
            %   Else    Loop until 1 sample is available
            %  
            % Recommendations/Observations:
            % 1) Threshold should be reasonably large (1/8 to 1/4
            %    device-buffer size)
            % 2) Min available samples should be significantly smaller than
            %    the threshold.

            % Input Params
            % samplesToAcquire, in principle, can be different from
            % samplesToGenerate; Session, however, forbids this
            samplesToAcquire = int32(analogInWaveformLength);
            samplesInAvailMinimum = int32(1); % int32(32);
            minInFreeThreshold = int32(512+1);
            digilentChannelInArray = obj.sessionChArrayToDigilentChArray(numAnalogInputChannels, sessionInputChIdx);
            channelInCount = int32(numAnalogInputChannels);
            
            inputWaveform = NaN(samplesToAcquire, numAnalogInputChannels);             
           
            % Might consider re-writing this to contain an array of
            % 2 structures (permits separation of concerns)
            setupParams = struct(...
                ...%Output Params
                'samplesToGenerate', samplesToGenerate,...
                'samplesOutFreeMinimum', samplesOutFreeMinimum,...
                'minOutFreeThreshold', minOutFreeThreshold,...
                'channelOutArray', digilentChannelOutArray,...
                'channelOutCount', channelOutCount,...
                ...%Input Params
                'samplesToAcquire', samplesToAcquire,...
                'samplesInAvailMinimum', samplesInAvailMinimum,...
                'minInFreeThreshold', minInFreeThreshold ,...
                'channelInArray', digilentChannelInArray,...
                'channelInCount', channelInCount);
            
            % Parameters:
            % handle, channelIdx, OutputBuffer, InputBuffer, setupParams, status)
            
            try                
            [status, ~] = ...
                mexFDwfForegroundSyncIO(deviceHandle,...
                                        channelIndex,...
                                        outputWaveform,...
                                        inputWaveform, ...
                                        setupParams,...
                                        char(0));
            catch err %#ok<NASGU>
                obj.digilentLocalizedError('digilent:discovery:outputSamplesLostExcessive');
            end
            
            numSamples = double(obj.NumberOfScans);
            inputWaveform = inputWaveform(1:numSamples, :);
            
            % If no error occurred as a result of calling the mex-file,
            % then update ScansOutputByHardware
            % See also: g910572            
            obj.processOutputEvent(obj.OutputQueueLength);
            
            daq.di.utility.throwOrWarnOnStatus(status);
            obj.processHardwareStop();
            obj.changeState('AcquiredDataWaiting');
            
            period = 1/obj.Rate;
            startTime = 0;
            % numsamples in data returned is what user asked for, not the
            % length of padded waveform
            numSamples = double(obj.NumberOfScans);
            endTime = startTime + (numSamples - 1) * period;
            timestamps = (startTime:period:endTime)';
            
            % Cannot presently run processAcquiredData more than once: call
            % it on the entire inputWaveform in one call.
            obj.processAcquiredData(obj.TriggerTime, ...
                                    timestamps,...
                                    inputWaveform);
           
            % No need to change state explicitly: that's handled by the
            % state-machine
            normalCompletionFlag = true;
        end        
        
        %% Channel Management helper functions
        
        % Look up channels by returning the contents of a ChannelRecord
        % structure
        function [numchannels, sessionChannelIndices, sessionChannels] = ...
                lookupSubsystemChannels(obj, subsystemRecord)
            numchannels = subsystemRecord.Count;
            sessionChannelIndices = subsystemRecord.Indices;
            sessionChannels = obj.Channels(sessionChannelIndices);
        end
        
        % Data-structure independent wrappers
        function [numchannels, sessionChannelIndices, sessionChannels] =  ...
               lookupAnalogInputChannels(obj)
           [numchannels, sessionChannelIndices, sessionChannels] = ...
               obj.lookupSubsystemChannels(obj.AnalogInputRecord);
        end
        
        function [numchannels, sessionChannelIndices, sessionChannels] =  ...
               lookupAnalogOutputChannels(obj)
           [numchannels, sessionChannelIndices, sessionChannels] = ...
               obj.lookupSubsystemChannels(obj.AnalogOutputRecord);           
        end
        
        % Digilent channels are referred to as '1', '2', etc.
        % (integer-strings).
        function [sessionChannelID] = lookupSessionChannelIDFromIndex(obj, sessionChannelIndex)
            sessionChannelID = str2double(obj.Channels(sessionChannelIndex).ID);
        end
        
        % Digilent channels are 0-indexed 32-bit integers 
        function [digilentChannelIdx] = sessionChIndexToDigilentChIndex(obj, sessionChannelIndex)
            digilentChannelIdx = int32(obj.lookupSessionChannelIDFromIndex(sessionChannelIndex)-1);
        end

        function [digilentChannelArray] = sessionChArrayToDigilentChArray(obj, numchannels, sessionChannelIndices)
            % Digilent channel indices start at 0 (-2 is explicitly invalid);
            % Column-vector of int32-values
            digilentChannelArray = repmat(int32(-2), 1, numchannels);
            for i = 1:numchannels
                digilentChannelArray(i) = obj.sessionChIndexToDigilentChIndex(sessionChannelIndices(i));
            end
        end               

        % Index = 
        % Multiple Channels => Synchronized mode: int32(-1)
        % Single Channel => int32(channel)
        function [channelIndex] = digilentAnalogOutputChannelIndex(obj, numchannels, channelIndices)
            if (numchannels > 1)
                channelIndex = daq.di.internal.const.Digilent.ChannelSynchronized; 
            elseif (numchannels == 1)
                % If we only have one channel, determine its index in the
                % Channel array of the Session
                chIdx = channelIndices(1);
                % Fetch the index corresponding to the Channel
                channelIndex = obj.sessionChIndexToDigilentChIndex(chIdx);
            else
                % This shouldn't occur if this function is called within
                % the Session infrastructure
                obj.localizedError('daq:Session:noOutputChannels');
            end
        end            
        
        %% Projection-Layer Wrappers / Helpers        

        function digilentEnableChannel(obj, deviceHandle, channelIndex) %#ok<INUSL>
            [status] = ...
                daq.di.dwf.FDwfAnalogOutEnableSet(deviceHandle, int32(channelIndex), ...
                daq.di.internal.const.Digilent.ChannelEnable);
            
            daq.di.utility.throwOrWarnOnStatus(status);
        end        
        
        % Output waveform is formed by processing the OutputQueue:
        % 1) Zero-Pad to an integral multiple of the buffer-size
        % 2) Normalize all values to lie between -1 and +1
        % 3) Enforce Session Channel-Order
        function [outputWaveform, waveformLength, maxOut] = formatWaveformOut(obj, channelCount, sessionChannelIndices)
            bufferSize = daq.di.internal.const.AnalogDiscovery.AnalogOutputBufferSize;
            queueLength = obj.OutputQueueLength;
            waveformLength = bufferSize * ceil(queueLength / bufferSize);
            
            % Note: MEX-file requires data be formatted as a column-based
            % array
            outputWaveform = zeros(waveformLength, channelCount);
            maxOut = zeros(1, channelCount);
            
            % Output waveform is stored as a vector between -1 and +1.
            % The amplitude of the wave (max/absolute-value) is stored as a
            % separate entry ('amplitude')
            if channelCount == 1
                maxOut(1) = max(abs(obj.OutputQueue(:, 1)));
                outputWaveform(1:queueLength, 1) = obj.OutputQueue(:, 1)./maxOut(1);
            else
                % Order of channels entered into session is respected
                for i = 1:channelCount
                    sessionIdx = obj.lookupSessionChannelIDFromIndex(sessionChannelIndices(i));
                    maxOut(sessionIdx) = max(abs(obj.OutputQueue(:, i)));
                    outputWaveform(1:queueLength, sessionIdx) = obj.OutputQueue(:, i)./maxOut(sessionIdx);
                end
            end
        end    
        
        function digilentPrefillWaveformBuffer(obj, deviceHandle, channelIndex, waveform)
        % 'waveform' should be no larger than the Analog-Output buffer size
            bufferSize = daq.di.internal.const.AnalogDiscovery.AnalogOutputBufferSize;
            if length(waveform) > bufferSize
                waveform = waveform(1:bufferSize);
            end
            
            [status, ~] = daq.di.dwf.FDwfAnalogOutDataSet(deviceHandle, channelIndex, waveform, int32(bufferSize)); 
            
            daq.di.utility.throwOrWarnOnStatus(status);                        
        end        
        
        % Analog-Input
        
        function digilentAnalogInputSetOffset(obj, deviceHandle, channelIndex, offset)
            [status] = ...
                daq.di.dwf.FDwfAnalogInChannelOffsetSet(deviceHandle, int32(channelIndex), offset);
            
            daq.di.utility.throwOrWarnOnStatus(status);
        end     
        
        function digilentAnalogInputSetDuration(obj, deviceHandle, duration)
            [status] = ...
                daq.di.dwf.FDwfAnalogInRecordLengthSet(deviceHandle, duration);
            
            daq.di.utility.throwOrWarnOnStatus(status);
        end   

        function digilentAnalogInputSetTriggerSource(obj, deviceHandle, enumeratedTriggerSource)
            obj.AnalogInputTriggerSource = enumeratedTriggerSource;
            
            [status] = daq.di.dwf.FDwfAnalogInTriggerSourceSet(deviceHandle, char(uint8(enumeratedTriggerSource)));
            daq.di.utility.throwOrWarnOnStatus(status);
        end
        
        function digilentAnalogInputSetTriggerFilter(obj, deviceHandle, enumeratedAcqFilter)
            obj.AcquisitionFilter = enumeratedAcqFilter;
            
            [status] = daq.di.dwf.FDwfAnalogInTriggerFilterSet(deviceHandle, int32(enumeratedAcqFilter));
            daq.di.utility.throwOrWarnOnStatus(status);          
        end  
        
        function digilentAnalogInputSetTriggerLengthCondition(obj, deviceHandle, enumeratedTriggerLengthCondition)
            obj.AnalogInputTriggerLengthCondition = enumeratedTriggerLengthCondition;
            
            [status] = daq.di.dwf.FDwfAnalogInTriggerLengthConditionSet(deviceHandle, int32(enumeratedTriggerLengthCondition));            
            daq.di.utility.throwOrWarnOnStatus(status);          
        end     
        
        function digilentAnalogInputSetTriggerChannel(obj, deviceHandle, triggerChannel)
            [status] = daq.di.dwf.FDwfAnalogInTriggerChannelSet(deviceHandle, triggerChannel);
            daq.di.utility.throwOrWarnOnStatus(status);
        end        
        
        function digilentAnalogInputSetTriggerLength(obj, deviceHandle, triggerLength)
            [status] = daq.di.dwf.FDwfAnalogInTriggerLengthSet(deviceHandle, triggerLength);
            daq.di.utility.throwOrWarnOnStatus(status);
        end
        
        function digilentAnalogInputSetTriggerHoldOff(obj, deviceHandle, triggerHoldOff)
            [status] = daq.di.dwf.FDwfAnalogInTriggerHoldOffSet(deviceHandle, triggerHoldOff);
            daq.di.utility.throwOrWarnOnStatus(status);
        end          
        
        % Analog-Output
        
        function digilentAnalogOutputSetOffset(obj, deviceHandle, channelIndex, offset)
            [status] = ...
                daq.di.dwf.FDwfAnalogOutOffsetSet(deviceHandle, int32(channelIndex), offset);
            
            daq.di.utility.throwOrWarnOnStatus(status);
        end   

        function digilentAnalogOutputSetFrequency(obj, deviceHandle, channelIndex, frequency)
            [status] = ...
                daq.di.dwf.FDwfAnalogOutFrequencySet(deviceHandle, int32(channelIndex), frequency);
            
            daq.di.utility.throwOrWarnOnStatus(status);
        end           
        
        function digilentAnalogOutputSetDuration(obj, deviceHandle, channelIndex, duration)
            [status] = ...
                daq.di.dwf.FDwfAnalogOutRunSet(deviceHandle, int32(channelIndex), duration);
            
            daq.di.utility.throwOrWarnOnStatus(status);
        end          
        
        function digilentAnalogOutputSetTriggerSource(obj, deviceHandle, channelIndex, enumeratedTrigger)
            obj.AnalogOutputTriggerSource = enumeratedTrigger;

            [status] = daq.di.dwf.FDwfAnalogOutTriggerSourceSet(deviceHandle, channelIndex, char(uint8(enumeratedTrigger)));
            daq.di.utility.throwOrWarnOnStatus(status);
        end

        % Set
                
        function digilentSetAmplitude(obj, deviceHandle, channelIndex, amplitude)
            [status] = ...
                daq.di.dwf.FDwfAnalogOutAmplitudeSet(deviceHandle, int32(channelIndex), amplitude);
            
            daq.di.utility.throwOrWarnOnStatus(status);
        end     
        
        function digilentSetNumRepeats(obj, deviceHandle, channelIndex, numRepeats)
            [status] = ...
                daq.di.dwf.FDwfAnalogOutRepeatSet(deviceHandle, int32(channelIndex), numRepeats);
            
            daq.di.utility.throwOrWarnOnStatus(status);
        end     

        function digilentSetRepeatTrigger(obj, deviceHandle, channelIndex, numTriggers)
            [status] = ...
                daq.di.dwf.FDwfAnalogOutRepeatTriggerSet(deviceHandle, int32(channelIndex), numTriggers);
            
            daq.di.utility.throwOrWarnOnStatus(status);
        end                
        
        function digilentSetGenerationMode(obj, deviceHandle, channelIndex, enumeratedGenMode)
            obj.GenerationMode = enumeratedGenMode;

            [status] = daq.di.dwf.FDwfAnalogOutFunctionSet(deviceHandle, channelIndex, uint8(enumeratedGenMode));
            daq.di.utility.throwOrWarnOnStatus(status);
        end
        
        function digilentSetAcquisitionMode(obj, deviceHandle, enumeratedAcqMode)
            obj.AcquisitionMode = enumeratedAcqMode;

            [status] = daq.di.dwf.FDwfAnalogInAcquisitionModeSet(deviceHandle, int32(enumeratedAcqMode));
            daq.di.utility.throwOrWarnOnStatus(status);
        end      
        
        function digilentSetAcquisitionFilter(obj, deviceHandle, channelIndex, enumeratedAcqFilter)
            obj.AcquisitionFilter = enumeratedAcqFilter;
            
            [status] = daq.di.dwf.FDwfAnalogInChannelFilterSet(deviceHandle, channelIndex, int32(enumeratedAcqFilter));
            daq.di.utility.throwOrWarnOnStatus(status);          
        end    
        
        function digilentSetAnalogIOMasterSwitch(obj, deviceHandle, masterSwitch)
            [status] = daq.di.dwf.FDwfAnalogIOEnableSet(deviceHandle, masterSwitch);
            daq.di.utility.throwOrWarnOnStatus(status);          
        end        

        function digilentEnableAnalogIOMasterSwitch(obj, deviceHandle)
            enableMasterSwitch = int32(1);
            obj.digilentSetAnalogIOMasterSwitch(deviceHandle, enableMasterSwitch);
        end        
        
        function digilentDisableAnalogIOMasterSwitch(obj, deviceHandle)
            disableMasterSwitch = int32(0);
            obj.digilentSetAnalogIOMasterSwitch(deviceHandle, disableMasterSwitch);
        end      
        
        function digilentSetAnalogIONode(obj, deviceHandle, ioChannel, ioNode, ioChannelState)
            [status] = daq.di.dwf.FDwfAnalogIOChannelNodeSet(deviceHandle, int32(ioChannel), int32(ioNode), double(ioChannelState));
            daq.di.utility.throwOrWarnOnStatus(status);
        end
      
        function digilentSetAnalogIOPowerSupplyNode(obj, deviceHandle, ioChannel, ioChannelState)
            powerSupplyNode = int32(0);
            obj.digilentSetAnalogIONode(deviceHandle, ioChannel, powerSupplyNode, ioChannelState);
        end
        
        function digilentSetAnalogIONegativeSupply(obj, deviceHandle, ioChannelState)
            negativeSupplyChannel = int32(1);
            obj.digilentSetAnalogIOPowerSupplyNode(deviceHandle, negativeSupplyChannel, ioChannelState);
        end
        
        function digilentSetAnalogIOPositiveSupply(obj, deviceHandle, ioChannelState)
            positiveSupplyChannel = int32(0);
            obj.digilentSetAnalogIOPowerSupplyNode(deviceHandle, positiveSupplyChannel, ioChannelState);
        end
    end
end
