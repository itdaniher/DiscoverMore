classdef SyncManager < daq.SyncManager
    %SyncManager SyncManager for Digilent Devices.
    %
    %    This class contains all vendor-specific code to managing trigger
    %    and clock connections.
    %
    %    This undocumented class may be removed in a future release.
    
    % Copyright 2011-2012 The MathWorks, Inc.
    
     methods(Hidden)
        function obj = SyncManager(session)
            obj@daq.SyncManager(session);
        end
    end
    
    
    %% Superclass methods this class implements
    methods (Hidden,  Access = protected)
        function resetImpl(obj)
            %resetImpl Handle daq.reset (which is usually delete)
            if isvalid(obj)
                delete(obj)
            end
        end
        
        function result = validateAndCorrectTriggerTypeHook(obj,~)
            result = [];
            obj.localizedError('digilent:discovery:featureUnavailable', 'addTriggerConnection');
        end
        
        function result = validateAndCorrectClockTypeHook(obj,~)
            result = [];
            obj.localizedError('digilent:discovery:featureUnavailable', 'addClockConnection');
        end
        
        function connectionBeingAddedImpl(obj)           %#ok<MANU>
        end
    end
    
    methods (Access = public, Hidden)
        function result = configurationRequiresExternalTriggerImpl(~)
            result = false;        
        end
    end
    
end