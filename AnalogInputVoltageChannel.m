classdef (Hidden) AnalogInputVoltageChannel <daq.AnalogInputVoltageChannel
    % AnalogOutputVoltageChannel All settings & operations for a Digilent
    % Analog Discovery input voltage channel added to a session.
    
    %   Copyright 2012-2013 The MathWorks, Inc.
    
    methods (Hidden)
        function obj = AnalogInputVoltageChannel(session, deviceInfo, channelID)
            %AnalogInputVoltageChannel All settings & operations for an analog input voltage channel added to a session.
            %    AnalogInputVoltageChannel(SUBSYSTEMTYPE,SESSION,DEVICEINFO,ID) Create a
            %    analog channel with SUBSYSTEMTYPE, SESSION, DEVICEINFO,
            %    and ID (see daq.Channel)
            
            
            obj@daq.AnalogInputVoltageChannel(session,deviceInfo,channelID);
            
        end
        
    end
    
    methods (Access = protected)
        
        function obj = channelPropertyBeingChangedHook(obj, propertyName, ~)
            %See geck: G642643
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