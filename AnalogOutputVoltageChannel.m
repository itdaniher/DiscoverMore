classdef (Hidden) AnalogOutputVoltageChannel < daq.AnalogOutputVoltageChannel
    % AnalogOutputVoltageChannel All settings & operations for a Digilent
    % Analog Discovery output voltage channel added to a session.
    
    %   Copyright 2012-2013 The MathWorks, Inc.
    
    methods (Hidden)
        function obj = AnalogOutputVoltageChannel(session, deviceInfo, channelID)
            %AnalogOutputVoltageChannel All settings & operations for an analog output voltage channel added to a session.
            %    AnalogOutputVoltageChannel(SUBSYSTEMTYPE,SESSION,DEVICEINFO,ID) Create a
            %    analog channel with SUBSYSTEMTYPE, SESSION, DEVICEINFO,
            %    and ID (see daq.Channel)
            
            obj@daq.AnalogOutputVoltageChannel(session,deviceInfo,channelID);
            
        end
        
    end
    
    methods (Access = protected)
        
        function obj = channelPropertyBeingChangedHook(obj, propertyName, ~)

            propertyName(strfind(propertyName,'Info'):end) = [];
            switch propertyName
                
                case 'TerminalConfig'
                    obj.Session.digilentLocalizedError('digilent:discovery:propertyNotApplicable', propertyName);
                case 'Coupling'
                    obj.Session.digilentLocalizedError('digilent:discovery:propertyNotApplicable', propertyName);
            end
        end
    end
end