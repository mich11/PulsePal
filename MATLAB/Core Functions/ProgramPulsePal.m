function ConfirmBit = ProgramPulsePal(ProgramMatrix)

% Import virtual serial port object into this workspace from base
global PulsePalSystem;
   OriginalProgMatrix = ProgramMatrix;
    
    % Convert Triggering address to bytes for each input channel (i.e.
    % input channel 1 triggers output channel 2 = 0010 = 2)
    TrigAddresses = cell2mat(ProgramMatrix(13:14,2:5));
    Chan1TrigAddressByte = uint8(bin2dec(num2str(TrigAddresses(1,:))));
    Chan2TrigAddressByte = uint8(bin2dec(num2str(TrigAddresses(2,:))));
    
    % Extract custom override byte (0 if parameterized, 1 if this channel uses custom
    % stimulus train 1, 2 if this channel uses custom stimulus train 2)
    FollowsCustomStimID = uint8(cell2mat(ProgramMatrix(15,2:5)));
    
    % Extract custom stim target byte (0 if custom timestamps point to
    % pulse onsets ignoring inter-pulse interval, 1 if custom timestamps point to burst onsets, 
    % ignoring inter-burst interval)
    CustomStimTarget = uint8(cell2mat(ProgramMatrix(16,2:5)));
    
    % Extract custom stim loop byte (0 if the sequence is to be played only
    % once, 1 if it is to be looped until the end of
    % StimulusTrainDuration.)
    CustomStimLoop = uint8(cell2mat(ProgramMatrix(17,2:5)));
    
    % Extract biphasic settings for the four channels - 0 if monophasic pulses, 1 if biphasic
    IsBiphasic = cell2mat(ProgramMatrix(2,2:5)); IsBiphasic = uint8(IsBiphasic);
    
    % Extract pulse voltage for phase 1
    Phase1Voltages = cell2mat(ProgramMatrix(3,2:5));
    % Extract pulse voltage for phase 2
    Phase2Voltages = cell2mat(ProgramMatrix(4,2:5));
    
    % Check if pulse amplitude is in range
    if (sum(Phase1Voltages > 10) > 0) || (sum(Phase1Voltages < -10) > 0) || (sum(Phase2Voltages > 10) > 0) || (sum(Phase2Voltages < -10) > 0)
        error('Error: Pulse voltages for Pulse Pal rev0.0.3 must be in the range -10V to 10V, and will be rounded to the nearest 78.125 mV.')
    end
    
    % Check if burst duration is defined when custom timestamps target
    % burst onsets
    for x = 1:4
        if CustomStimTarget(x) == 1
            BDuration = ProgramMatrix{9,1+x};
            if BDuration == 0
                error(['Error in output channel ' num2str(x) ': When custom stimuli target burst onsets, a non-zero burst duration must be defined.'])
            end
        end
    end

    % For parameterized mode, check whether partial pulses will be
    % generated, and adjust specified stimulus duration to exclude them.
    for x = 1:4
        BiphasicChannel = ProgramMatrix{2,1+x};
        if BiphasicChannel == 0
            PulseDuration = ProgramMatrix{5,1+x};
        else
            PulseDuration = ProgramMatrix{5,1+x} + ProgramMatrix{6,1+x} + ProgramMatrix{7,1+x};
        end
        PulseTrainDuration = ProgramMatrix{11,1+x};
        PulseOverlap = rem(PulseTrainDuration, PulseDuration);
        if PulseOverlap > 0
            PulseTrainDuration = PulseTrainDuration - PulseOverlap;
            ProgramMatrix{11,1+x} = PulseTrainDuration;
        end
    end
    
    
    % Extract voltages for phases 1 and 2
    Phase1Voltages = uint8(ceil(((Phase1Voltages+10)/20)*255));
    Phase2Voltages = uint8(ceil(((Phase2Voltages+10)/20)*255));
    
    % Extract input channel settings
    
    InputChanMode = uint8(cell2mat(ProgramMatrix(2,8:9))); % if 0, "Normal mode", triggers on low to high transitions and ignores triggers until end of stimulus train. 
    % if 1, "Toggle mode", triggers on low to high and shuts off stimulus
    % train on next high to low. If 2, "Button mode", triggers on low to
    % high and shuts off on high to low.
    
    
    % Convert time data to microseconds
    TimeData = uint32(cell2mat(ProgramMatrix(5:12, 2:5))*1000000);
    
    % Ensure time data is within range
    if sum(sum(rem(TimeData, 100))) > 0
        errordlg('Non-zero time values for Pulse Pal rev0.4 must be multiples of 100 microseconds. Please check your program matrix.', 'Invalid program');
    end
    
    % Arrange program into a single byte-string
    FormattedProgramTimestamps = TimeData(1:end); 
    SingleByteOutputParams = [IsBiphasic; Phase1Voltages; Phase2Voltages; FollowsCustomStimID; CustomStimTarget; CustomStimLoop];
    FormattedParams = [SingleByteOutputParams(1:end) Chan1TrigAddressByte Chan2TrigAddressByte InputChanMode];
    
    % Send program
    fwrite(PulsePalSystem.SerialPort, 73, 'uint8'); % Instruct PulsePal to recieve a new program with byte 73
    fwrite(PulsePalSystem.SerialPort, FormattedProgramTimestamps, 'uint32'); % Send 32 bit time data
    fwrite(PulsePalSystem.SerialPort, FormattedParams, 'uint8'); % Send 8-bit params
    ConfirmBit = fread(PulsePalSystem.SerialPort, 1); % Get confirmation
    PulsePalSystem.CurrentProgram = OriginalProgMatrix; % Update Pulse Pal object