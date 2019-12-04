function compute_ICs_new(filepath,filename,outpath,interpolate_channels,cleandata,highpass,include_EOG)
% function compute_ICs(filepath,filename,outpath,interpolate_channels,cleandata,highpass,include_EOG)
% perform ICA and save result. 
%
% If interpolate_channels = 'yes', bad channels are interpolated prior to ICA (default: false).
% If cleandata = 'yes'; muscle artefacts are removed (only works on epoched data), and event codes >
% 10000 are removed as these are assumed to contain artefacts. Also, the average activation across
% each epoch is removed (default: false).
% If highpass = .1; (default = 'no') the algorithm also applies a highpass filter prior to ICA.
% If include_EOG = 'yes', the algorithm applies ICA to EOG channels too (default = 'no').
%
% J.J.Fahrenfort, VU, 2014, 2016, 2019
if nargin < 7
    include_EOG = true;
end
if nargin < 6
    highpass = false;
end 
if nargin < 5
    cleandata = false;
end
if nargin < 4
    interpolate_channels = false;
end
if nargin < 3
    outpath = filepath;
end
if isempty(outpath)
    outpath = filepath;
end
if ~exist(filepath,'dir')
    error('the input directory does not exist');
end
if ~exist(outpath,'dir')
    mkdir(outpath);
end
[~,filename,~] = fileparts(filename);
if ischar(interpolate_channels)
    if strcmpi(interpolate_channels,'true') || strcmpi(interpolate_channels,'yes') || string2double(interpolate_channels) == 1
        interpolate_channels = true;
    else
        interpolate_channels = false;
    end
end
if ischar(cleandata)
    if strcmpi(cleandata,'true') || strcmpi(cleandata,'yes') || string2double(cleandata) == 1
        cleandata = true;
    else
        cleandata = false;
    end
end
if ischar(highpass)
    highpass = string2double(highpass);
    if isnan(highpass) % 'no' or 'yes' will make highpass false, only a number will do
        highpass = false;
    end
end
if ischar(include_EOG)
    if strcmpi(include_EOG,'true') || strcmpi(include_EOG,'yes') || string2double(include_EOG) == 1
        include_EOG = true;
    else
        include_EOG = false;
    end
end
EEG = pop_loadset('filename',[ filename '.set'],'filepath',filepath);

% double check whether channel location information is present
channelnames = {EEG.chanlocs(:).labels};
nopos_channels = [];
for cEl=1:length(EEG.chanlocs)
    if (any(isempty(EEG.chanlocs(1,cEl).X)&isempty(EEG.chanlocs(1,cEl).Y)&isempty(EEG.chanlocs(1,cEl).Z)&isempty(EEG.chanlocs(1,cEl).theta)&isempty(EEG.chanlocs(1,cEl).radius)))
        nopos_channels = [nopos_channels cEl];
    end
end

% find EEG channels
eeg_channels = select_channels(channelnames,'EEG');
eeg_eog_channels = select_channels(channelnames,'EEG_EOG');
if isempty(eeg_channels)
    error('stopping now, there are no EEG channels in this set??');
end

% in case some EEG channels do not have location information
if any(ismember(eeg_channels,nopos_channels))
    disp(['WARNING: Channels ' num2str(nopos_channels) ' have incomplete location information. Now attempting to read in location information.']);
    EEG = pop_chanedit(EEG, 'lookup', trycapfile);
end

% apply highpass filter
if highpass ~= false
    EEG = pop_eegfiltnew(EEG, highpass, 0);
end

% interpolate bad channels
if interpolate_channels
    % read in text file that says which electrodes to interpolate (if present)
    % This way you can use the same electrodes that are interpolated in the
    % actual analysis dataset
    if ~isempty(dir([filepath filesep 'interpolated_electrodes_*.txt'])) 
        if exist([filepath filesep 'interpolated_electrodes_' filename '.txt'],'file')
            disp(['loading electrodes to interpolate from file ' filename '.txt']);
            rejected_electrodes = textread([filepath filesep 'interpolated_electrodes_' filename '.txt'],'%s');
            indelec = find(ismember(channelnames,rejected_electrodes));
        else
            indelec = []; % if no file is specified, no electrodes are interpolated
        end
    else % or detect (really) bad electrodes 
        disp(['detecting bad elecrodes for ' filename ]);
        [ ~, indelec ] = pop_rejchan(EEG, 'threshold',10, 'norm', 'on', 'measure', 'prob','elec',eeg_channels); 
    end
    rejected_electrodes = channelnames(indelec);
    if ~isempty(rejected_electrodes)
        EEG = pop_interp(EEG, indelec, 'spherical');
        fid = fopen([outpath filesep 'interpolated_electrodes_' filename '.txt'], 'wt' );
        for c = 1:numel(rejected_electrodes)
            fprintf( fid, '%s\n', rejected_electrodes{c});
        end
        fclose(fid);
    end
end

% muscle artifact detection, only works on epoched data
if cleandata 
    
    % remove bad data
    events = pop_exportepoch(EEG);              % these are the relevant events
    toreject = events > 10000;                  % identify events marked as bad
    EEG = pop_rejepoch(EEG, toreject, false);   % reject those events
    
    % convert to FT format for cleaning
    FT_EEG = eeglab2ft(EEG);
    
    % baseline correction
    cfg = [];
    cfg.baseline = [min(FT_EEG.time{1}) 0];
    cfg.channel = 'all';
    cfg.parameter = 'trial';
    FT_EEG = ft_timelockbaseline(cfg,FT_EEG);
    
    [~, boollist] = muscle_removal(FT_EEG);
    clear FT_EEG;
    
    % remove artefacts
    EEG = pop_select(EEG,'notrial',find(boollist));
    
    % remove baseline across entire window
    EEG = pop_rmbase(EEG,[]);
    
end

% use only EEG channels or use EEG and EOG channels for ICA
if include_EOG
    chans4ICA = eeg_eog_channels;
else
    chans4ICA = eeg_channels;
end
disp(['running ICA on ' num2str(numel(chans4ICA)) ' channels.']);
EEG = pop_runica(EEG,'icatype','runica','extended', 1,'chanind',chans4ICA);
pop_saveset(EEG, 'filename',[filename '.set'],'filepath',outpath);

% generate and save plot of the components, taking out EOG for clarity
EEG = pop_select(EEG, 'channel', eeg_channels);
pop_topoplot_savepng(EEG,0, 1:numel(eeg_channels), [outpath filesep filename '_ICs.png']);

