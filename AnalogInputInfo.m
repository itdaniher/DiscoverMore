classdef (Hidden) AnalogInputInfo < daq.AnalogInputInfo
    % AnalogOutputInfo analog input subsystem info for Digilent
    % Analog Discovery Devices
    %
    %   This undocumented class may be removed in a future release.    
    
    %   Copyright 2012-2013 The MathWorks, Inc.

    methods (Hidden)
        function obj = AnalogInputInfo(deviceIndex, deviceHandle)
            
            %Initialize the properties here. They'll be set by query device
            %to device specific values. These are
            
            %Get measurement types available
            measurementTypesAvailable = cellstr('Voltage');
            
            %Get default measurement type
            defaultMeasurementType = 'Voltage';
            
            nativeDataType = 'double';
            
            %Get AIPhysicalChannels
            [status, channelCount] = daq.di.dwf.FDwfEnumAnalogInChannels(int32(deviceIndex), int32(0));
            daq.di.utility.throwOrWarnOnStatus(status);
            %Digilent IDs their channels using int32 indices
            for idxChannels = 1:channelCount
                AIPhysicalChans{1,idxChannels} = num2str(idxChannels); %#ok<AGROW>
            end
            
            %Now query the device allowed Rates
            [status, minRate, maxRate] = daq.di.dwf.FDwfAnalogInFrequencyInfo(deviceHandle, double(0), double(0));
            daq.di.utility.throwOrWarnOnStatus(status);
            

            % g910619: show appropriate device limitations
            % Given the present driver limitations, the rate limit for a
            % streaming data for single subsystem is 1 MHz (the advertised
            % maximum rate of 100 MHz is possible for a single-buffer
            % acquisition only).
            
            maxRate = min(maxRate, 1e6);   
            
            rateLimitInfo = daq.internal.ParameterLimit(minRate, maxRate);
            
            %Digilent returns the min and max ranges. Since the terminals
            %are only differential, the min and max Voltages for each range
            %are determined by the default voltage offset(0V) and the Range
            [status, minRange, maxRange, numRanges] = daq.di.dwf.FDwfAnalogInChannelRangeInfo(deviceHandle, double(0), double(0), double(0));
            daq.di.utility.throwOrWarnOnStatus(status);

            
            rangesAvailableForDifferential              = daq.Range.empty();
            %Create a Range array. Only two are returned now  so this is
            %trivial.
            rangesReturned = [minRange maxRange];
            for idxRange = 1:numRanges
                rangesAvailableForDifferential(end+1) = daq.Range(-rangesReturned(idxRange)/2, rangesReturned(idxRange)/2, 'Volts');  %#ok<AGROW>
            end
            
            rangesAvailableForSingleEnded               = daq.Range.empty();
            rangesAvailableForSingleEndedNonReferenced  = daq.Range.empty();
            rangesAvailableForPseudoDifferential        = daq.Range.empty();
            
            %Get the ADC resolution in bits
            [status, resolutionBits] = daq.di.dwf.FDwfEnumAnalogInBits(deviceIndex, int32(0));
            daq.di.utility.throwOrWarnOnStatus(status);
            resolution = resolutionBits;
            %All channels are Simultaneously being scanned
            sampleTypeInfo = daq.SampleType.Simultaneous;
            %Only DC coupling is available on Discovery
            couplingsAvailableInfo   = daq.Coupling.DC;
            %Only Differential terminals are available on Discovery
            terminalConfigsAvailableInfo = daq.TerminalConfig.Differential;
            %On Demand operations are supported by Discovery
            onDemandOperationsSupported = true;
            
            
            %Now call superclass constructor
            obj@daq.AnalogInputInfo(...
                measurementTypesAvailable,...
                defaultMeasurementType,...
                nativeDataType,...
                AIPhysicalChans,...
                rateLimitInfo,...
                rangesAvailableForDifferential,...
                rangesAvailableForSingleEnded,...
                rangesAvailableForSingleEndedNonReferenced,...
                rangesAvailableForPseudoDifferential,...
                resolution,...
                couplingsAvailableInfo,...
                sampleTypeInfo,...
                terminalConfigsAvailableInfo,...,...
                onDemandOperationsSupported)
            
            
            
            
        end
        
        
    end
end