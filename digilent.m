classdef (Hidden) digilent < daq.VendorInfo
    %digilent Demonstration adaptor for Digilent hardware
    %
    %    This class represents Digilent Analog Discovery hardware.
    %
    %    This undocumented class may be removed in a future release.
    
    % Copyright 2011-2013 The MathWorks, Inc.
    
    properties (Constant, Hidden)
        versionStringLength = 36;
    end
    
    methods
        function obj = digilent()
            %Constructor for digilent VendorInfo object
            %Initialize properties
            
            isOperational = true;
            % Localized operational text
            operationalSummary = getString(message('daq:general:operationalText'));
            
            % Minimum acceptable version of dwf (major.minor) -- this
            % cannot be a object constant, because we cannot access the
            % object until after the base class is instantiated
            minimumAcceptableDriverVersion = 2.30;
            driverVersion = 'Unknown';
            
            try
                % Try to load the mex file
                mexdwf()
            catch e
                isOperational = false;
                operationalSummary = daq.di.digilent.diagnoseMexLoadingProblem(e, minimumAcceptableDriverVersion);
            end
            
            if isOperational
                % Get the complete version number. A maximum of 36 chars allowed
                [status,driverVersion] = daq.di.dwf.FDwfGetVersion(blanks(daq.di.digilent.versionStringLength));
                daq.di.utility.throwOrWarnOnStatus(status);
                
                % convert the version string to a decimal number
                versionDigits = regexp(driverVersion, '[0-9]', 'match');
                versionNum    = str2double(versionDigits{1}) + str2double(versionDigits{2})* 0.1 + str2double(versionDigits{3})*0.01;
                
                if versionNum<minimumAcceptableDriverVersion
                    % Give error if below minimum version
                    isOperational = false;
                    % We're in the constructor, so we have to access the
                    % message catalog directly
                    operationalSummary = getString(message('digilent:discovery:doesNotMeetMinimumVersion',num2str(minimumAcceptableDriverVersion)));
                end
            end
            
            obj@daq.VendorInfo('digilent',...             % id
                'Digilent Inc.',...                 % fullName
                getAdaptorVersion(),...             % adaptorVersion
                driverVersion,...                   % driverVersion
                daq.di.digilent.getDigilentDriverPath);    % driverPath
            obj.IsOperational = isOperational;
            obj.OperationalSummary = operationalSummary;
            
            
            % Try loading the message catalog
            m = message('digilent:discovery:featureUnavailable', 'Test');
            try
                m.getString();
                obj.IsCatalogLoaded = 1;
            catch %#ok
                try
                    package = hwconnectinstaller.PackageInstaller.getSpPkgInfo('Digilent Analog Discovery');
                    [~] = registerrealtimecataloglocation(package.RootDir);
                    obj.IsCatalogLoaded = 1;
                catch %#ok
                    obj.IsCatalogLoaded = 0;
                end
                
            end
            
        end
    end
    
    % Private properties
    properties (Access = private)
        OperationalSummary % Summary of the operational status of the adaptor
    end
    
    properties (GetAccess = public, SetAccess = private, Hidden)
        IsCatalogLoaded
    end
    
    methods (Access = protected)
        function registerDevicesImpl(obj)
            
            % Method to get the Digilent devices detected and add them
            
            %Int32(0)= Flag to enumerate all device types. The second arg is the number of
            %devices found int32
            numDevices = int32(0);
            [status, numDevices] = daq.di.dwf.FDwfEnum(int32(0), numDevices);
            daq.di.utility.throwOrWarnOnStatus(status);
            
            % loop over all the devices
            for deviceIndex = 0:numDevices-1
                % Check if the device is already opened if it is, issue a
                % warning
                
                % Init
                isDeviceOpened = int32(0);
                
                [status, isDeviceOpened] = daq.di.dwf.FDwfEnumDeviceIsOpened(int32(deviceIndex), isDeviceOpened);
                daq.di.utility.throwOrWarnOnStatus(status);
                
                % Get the user specified or default userName
                [status, devName] = daq.di.dwf.FDwfEnumDeviceName(int32(deviceIndex), blanks(32));
                daq.di.utility.throwOrWarnOnStatus(status);
                if ~isDeviceOpened %then add the device
                    
                    obj.addDevice(daq.di.DeviceInfo(obj,devName, deviceIndex));
                    
                else
                    daq.internal.BaseClass.localizedWarning('digilent:discovery:deviceAlreadyOpenedWarn', devName);
                end
                
            end
            
            % Register the session class for digilent
            obj.registerSessionFactory('daq.di.Session');
            
        end
        
        function summaryText = getOperationalSummaryImpl(obj)
            summaryText = obj.OperationalSummary;
        end
        
    end
    
    methods (Static, Access = private)
 
        function operationalSummary = diagnoseMexLoadingProblem(mException, minimumAcceptableDriverVersion)
            
            %This static method helps diagnose why the mexdwf() function
            %call fails. It could be either that:
            
            % (1) The file itself is not available
            % (2) The file is corrupt (not the right binary)
            % (3) The driver version is not correct
            % (4) The driver is not installed
            % (5) Unknown error with the driver or MEX file
            
            % Note: This function follows the same semantics as the NI
            % diagnoseMexLoadingProblem()
            
            currentFileLocation = which('daq.di.digilent'); % This is where the support package files live
            expectedFilePath = [strrep(currentFileLocation, 'digilent.m', '') 'private\' 'mexdwf.' mexext];
            
            
            switch mException.identifier
                case 'MATLAB:UndefinedFunction'
                    % First make sure the MEX file exists.
                    if exist(expectedFilePath, 'file') == 0
                        operationalSummary = getString(message('digilent:discovery:MEXFileNotFound',...
                            expectedFilePath));
                    else
                        % Ensure that the MEX file is valid which is captured in
                        % the mException.message.
                        if ~isempty(strfind(mException.message, 'is not a valid'))
                            operationalSummary = getString(message('digilent:discovery:MEXFileCorrupt',...
                                mException.message));
                        else
                            % We don't have enough information to give a specific error.
                            operationalSummary = getString(message('digilent:discovery:couldNotLoadMEXFile',...
                                mException.identifier, mException.message));
                        end
                    end
                case 'MATLAB:invalidMEXFile'
                    % invalidMEXFile could mean that the file exists but
                    % isn't valid or that the Digilent driver is not installed
                    % or is not the right revision. The exception message
                    % holds the key.
                    if ~isempty(strfind(mException.message, 'is not a valid'))
                        % The file is really corrupt.
                        operationalSummary = getString(message('digilent:discovery:MEXFileCorrupt',...
                            mException.message));
                    elseif  ~isempty(strfind(mException.message, 'The specified module could not be found'))
                        % This could mean that the MEX file does not exist.
                        % But if it existed and was removed it will be in
                        % the toolboxcache, so we can't use the EXIST or
                        % WHICH. DIR will tell us if the file really is
                        % there and works on both Windows and UNIX.
                        listing = dir(expectedFilePath);
                        if isempty(listing)
                            operationalSummary = getString(message('digilent:discovery:MEXFileNotFound',...
                                expectedFilePath));
                        else
                            % If our MEX file is there then the Digilent
                            % drivers are not installed or are not at the
                            % right revision.
                            operationalSummary = getString(message('digilent:discovery:MEXLoadErrorDriverIssue',...
                                num2str(minimumAcceptableDriverVersion), mException.message));
                        end
                    elseif ~isempty(strfind(mException.message, 'The specified procedure could not be found'))
                        % This means that the Digilent driver is not the
                        % right version.
                        operationalSummary = getString(message('digilent:discovery:MEXLoadErrorDriverIssue',...
                            num2str(minimumAcceptableDriverVersion), mException.message));
                    else
                        % We don't have enough information to give a specific error.
                        operationalSummary = getString(message('digilent:discovery:couldNotLoadMEXFile',...
                            mException.identifier, mException.message));
                    end
                otherwise
                    % We don't have a specific handler for this type of
                    % failure.  Give general diagnostic.
                    operationalSummary = getString(message('digilent:discovery:couldNotLoadMEXFile',...
                        mException.identifier, mException.message));
            end
        end
        
        function [driverPath] = getDigilentDriverPath()
            %If we are on Win7
            sysRoot = getenv('SystemRoot');
            win7FilePath = [ sysRoot '\System32\dwf.dll'];
            %If we are on XP: Hard-coding for now
            winXPFilePath = 'C:\Program Files\Digilent\Waveforms\dwf.dll';
            if exist(win7FilePath, 'file')
                driverPath = win7FilePath;
            elseif exist(winXPFilePath, 'file')
                driverPath = winXPFilePath;
            else
                driverPath = 'n\a';
            end
        end
        
    end
    
end