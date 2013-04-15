classdef (Hidden) AnalogOutputInfo < daq.AnalogOutputInfo
    % AnalogOutputInfo analog output subsystem info for Digilent
    % Analog Discovery Devices
    %
    %   This class represents a analog output subsystem on 
    %   Analog Discovery devices from Digilent 
    %
    %   This undocumented class may be removed in a future release.    
    
    %   Copyright 2012-2013 The MathWorks, Inc.
    
    methods (Hidden)
        function obj = AnalogOutputInfo(deviceHandle)
                        
            %Initialize the properties here in super-class constructor
            %order. They will be set by query device to device-specific
            %values. These are:
            
            %Get measurement types available
            measurementTypesAvailable = cellstr('Voltage');
            
            %Get default measurement type
            defaultMeasurementType = 'Voltage';
            
            nativeDataType = 'double';
            
            % Get AOPhysicalChannels (Step 1 of 2): Get the channel count
            % FDwfAnalogOutCount(handle, pcCount)
            [status, channelCount] = daq.di.dwf.FDwfAnalogOutCount(deviceHandle, int32(0));
            daq.di.utility.throwOrWarnOnStatus(status);
            
            % Get AOPhysicalChannels  (Step 2 of 2): Define array of physical channels            
            % Digilent channels are enumerated using int32 indices
            % Session channel-indices are one-based.
            % Digilent channel-indices are zero-based
            
            
            AOPhysicalChannels = cell(1, channelCount);
            for idxChannels = 1:channelCount
                AOPhysicalChannels{1,idxChannels} = num2str(idxChannels); 
            end
            
            % Get Rate-Limit Info (Step 1 of 2): Ask the device for allowed output-rates
            
            % At present, all channels are identical but there is no
            % guarantee that this will always be true. 
            % The smallest maximum and largest minimum are used.
            
            % FDwfAnalogOutFrequencyInfo(handle, idxChannel, min, max)
            % Preallocate arrays: -1 is not a valid rate to start
            minRateTemp = repmat(-1, channelCount, 1);
            maxRateTemp = repmat(-1, channelCount, 1);
            
            for idxChannels = 1:channelCount
                [status, minRateTemp(idxChannels), maxRateTemp(idxChannels)] = ...
                    daq.di.dwf.FDwfAnalogOutFrequencyInfo(deviceHandle, int32(idxChannels-1), double(0), double(0)); 
                daq.di.utility.throwOrWarnOnStatus(status);
            end
            
            minRate = max(minRateTemp);
            maxRate = min(maxRateTemp);   
            
            % g910619: show appropriate device limitations
            % Given the present driver limitations, the rate limit for a
            % streaming data for single subsystem is 1 MHz (the advertised
            % maximum rate of 100 MHz is possible for a single-buffer
            % generation only).
            
            maxRate = min(maxRate, 1e6);                    
            
            % Get Rate-Limit Info (Step 2 of 2): Pass output-rates into ParameterLimit
            rateLimitInfo = daq.internal.ParameterLimit(minRate,maxRate);

            % Define available ranges for Differential, Single-Ended,
            % Non-Referenced Single-Ended, and Pseudo-Differential 
            % At present (2012), the only single-ended outputs are
            % supported by the hardware.
            
            % At present, all channels are identical but there is no
            % guarantee that this will always be true. 
            % The smallest maximum and largest minimum are used.
            
            % Preallocate arrays: smallest minimum, largest maximum          
            minRangeTemp = repmat(-Inf, channelCount, 1);
            maxRangeTemp = repmat(+Inf, channelCount, 1);            

            for idxChannels = 1:channelCount
                [status, minRangeTemp(idxChannels), maxRangeTemp(idxChannels)] = ...
                    daq.di.dwf.FDwfAnalogOutAmplitudeInfo(deviceHandle, int32(idxChannels-1), double(0), double(0)); 
                daq.di.utility.throwOrWarnOnStatus(status);
            end
            
            minRange = max(minRangeTemp);
            maxRange = min(maxRangeTemp);
            
            rangesAvailableForDifferential              = daq.Range.empty();
            rangesAvailableForSingleEnded               = daq.Range.empty();
            rangesAvailableForSingleEndedNonReferenced  = daq.Range.empty();
            rangesAvailableForPseudoDifferential        = daq.Range.empty();
            
            % daq.Range(min, max, units)
            rangesAvailableForSingleEnded(end+1) = daq.Range(minRange, maxRange, 'Volts');

            %Get the DAC resolution in bits: there is no function analogous
            %to the ADC input for analog out. (Maybe request an API
            %update?)
            resolution = int32(14);

            %Only SingleEnded terminals are available on Discovery
            terminalConfigsAvailableInfo = daq.TerminalConfig.SingleEnded;
            %On Demand operations are supported by Discovery
            onDemandOperationsSupported = true;
            
            
            %Now call superclass constructor
            obj@daq.AnalogOutputInfo(...
                measurementTypesAvailable,...
                defaultMeasurementType,...
                nativeDataType,...
                AOPhysicalChannels,...
                rateLimitInfo,...
                rangesAvailableForDifferential,...
                rangesAvailableForSingleEnded,...
                rangesAvailableForSingleEndedNonReferenced,...
                rangesAvailableForPseudoDifferential,...
                resolution,...
                terminalConfigsAvailableInfo,...,...
                onDemandOperationsSupported)

        end
   
    end
end