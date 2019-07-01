function adam_average_grouptraining(cfg,folder_name)
% ADAM_AVERAGE_ITERATIONS computes average across group-trained data for every subject, and saves the
% result. Create group trained data by using file_list_grouptrain to create file combinations when
% running the first level analysis using adam_MVPA_firstlevel.
%
% Use as:
%   adam_average_grouptraining(cfg)
%
% The cfg (configuration) input structure can contain the following optional parameters:
%
%       cfg.startdir         = '' (default); ADAM will pop-up a selection dialog when running
%                              adam_compute_group_MVPA. The cfg.startdir parameter allows you to
%                              specify the starting directory of this selection dialog. Use this
%                              parameter to specify where the results of all the first level
%                              analyses are located. When you do not specify cfg.startdir, you will
%                              be required to navigate from your Matlab root folder to the desired
%                              results directory every time you run a group analysis.
%       cfg.keepfiles        = false (default): remove the files on which the average is based.
%                              Alternatively set to true, in which all the files will be kept in a
%                              directory called 'grouptrain'.
%
% The output (averaged result) is saved in the same folder, as though it would be a regular
% analysis. This can subsequently be read in using adam_compute_group_MVPA. The analyses on which
% these averages are based are moved to a subfolder which is called 'grouptrain'.
% 
% part of the ADAM toolbox, by J.J.Fahrenfort, VU, 2017/2018/2019
% 
% See also: ADAM_MVPA_FIRSTLEVEL, ADAM_COMPUTE_GROUP_MVPA, ADAM_PLOT_MVPA

% First get some settings
if nargin<2
    folder_name = '';
end
mask = [];
plot_order = {};
reduce_dims = '';
freqlim = [];
keepfiles = false;
channelpool = '';

% backwards compatibility
plot_dim = 'time_time'; % default, 'time_time' or 'freq_time'
v2struct(cfg);
if exist('one_two_tailed','var')
    error('The cfg.one_two_tailed field has been replaced by the cfg.tail field. Please replace cfg.one_two_tailed with cfg.tail using ''both'', ''left'' or ''right''. See help for further info.');
end
if exist('plotmodel','var')
    plot_model = plotmodel;
    cfg.plot_model = plot_model;
    cfg = rmfield(cfg,'plotmodel');
end
if exist('get_dim','var')
    plot_dim = get_dim;
    cfg = rmfield(cfg,'get_dim');
end
if strcmpi(plot_dim,'frequency_time') || strcmpi(plot_dim,'time_frequency') || strcmpi(plot_dim,'time_freq')
    plot_dim = 'freq_time';
end
if exist('plotorder','var')
    plot_order = plotorder;
    cfg.plot_order = plot_order;
    cfg = rmfield(cfg,'plotorder');
end
cfg.plot_dim = plot_dim;
cfg.keepfiles = keepfiles;

% Main routine, is a folder name specified? If not, pop up selection dialog
if isempty(folder_name)
    if ~isfield(cfg,'startdir')
        cfg.startdir = '';
        disp('NOTE: it is easier to select a directory when you indicate a starting directory using cfg.startdir, otherwise you have to start selection from root every time...');
    end
    folder_name = uigetdir(cfg.startdir,'select directory to plot');
end
if ~exist(folder_name,'dir')
    error('no folder was selected or the specified folder does not exist');
end
cfg.folder = folder_name;

% where am I?
ndirs = drill2data(folder_name,channelpool);
if isempty(plot_order)
    dirz = dir(folder_name);
    dirz = {dirz([dirz(:).isdir]).name};
    plot_order = dirz(cellfun(@isempty,strfind(dirz,'.')));
    if ndirs == 1
        [folder_name, plot_order] = fileparts(folder_name);
        plot_order = {plot_order};
    elseif ndirs > 2
        error('You seem to be selecting a directory that is too high in the hiearchy, drill down a little more.');
    end
    cfg.plot_order = plot_order;
elseif ndirs ~= 2
    error('You seem to be selecting a directory that is either too high or too low in the hiearchy given that you have specified cfg.plot_order. Either remove cfg.plot_order or select the appropriate level in the hierarchy.');
else
    dirz = dir(folder_name);
    dirz = {dirz([dirz(:).isdir]).name};
    dirz = dirz(cellfun(@isempty,strfind(dirz,'.')));
    for cPlot = 1:numel(plot_order)
        dirindex = find(strcmpi(plot_order{cPlot},dirz)); 
        if isempty(dirindex) % if an exact match cannot be made, look only for the pattern in the first sequency of characters
            dirindex = find(strcmpi(plot_order{cPlot},dirz,numel(plot_order{cPlot}))); 
        end
        if isempty(dirindex)
            error(['cannot find condition ' plot_order{cPlot} ' specified in cfg.plot_order']);
        elseif numel(dirindex) > 1
            error(['cannot find a unique condition for the pattern ' plot_order{cPlot} ' specified in cfg.plot_order']);
        else
            plot_order{cPlot} = dirz{dirindex};
        end
    end       
    if ~all(ismember(plot_order,dirz))
        error('One or more of the folders specified in cfg.plot_order cannot be found in this results directory. Change cfg.plot_order or select a different directory for plotting.');
    end
end

% loop through directories (results folders)
for cdirz = 1:numel(plot_order)
    subcompute_group_MVPA(cfg, [folder_name filesep plot_order{cdirz}]);
end

% subroutine for each condition
function subcompute_group_MVPA(cfg, folder_name)

% set defaults
channelpool = '';
read_confidence = false;
niterations = [];

% unpack settings
v2struct(cfg);

% set defaults
if isempty(channelpool)
    chandirz = dir(folder_name);
    chandirz = {chandirz([chandirz(:).isdir]).name};
    chandirz = sort(chandirz(cellfun(@isempty,strfind(chandirz,'.'))));
    channelpool = chandirz{1};
    disp(['No cfg.channelpool specified, defaulting to channelpool ' channelpool ]);
end

% some logical checking: is this a frequency folder?
freqfolder_contains_time_time = ~isempty(dir([folder_name filesep channelpool filesep 'freq*'])); 
freqfolder_contains_freq_time = ~isempty(dir([folder_name filesep channelpool filesep 'allfreqs']));
freqfolder = any([freqfolder_contains_time_time freqfolder_contains_freq_time]);
if freqfolder
    if strcmpi(plot_dim,'freq_time') && freqfolder_contains_freq_time
        plotFreq = {[filesep 'allfreqs']};
    elseif strcmpi(plot_dim,'freq_time')
        disp('WARNING: freq_time is not availaible in this folder, defaulting to cfg.plot_dim = ''time_time''');
        plot_dim = 'time_time';
    end
    if strcmpi(plot_dim,'time_time') && freqfolder_contains_time_time
        if isempty(freqlim)
            freqlim = input('What frequency or frequency range should I extract (e.g. type [2 10] to average between 2 and 10 Hz)? ');
        end
        if numel(freqlim) > 1 % make a list of frequencies over which to average
            freqlist = dir([folder_name filesep channelpool filesep 'freq*']); freqlist = {freqlist(:).name};
            for c=1:numel(freqlist); freqsindir(c) = string2double(regexprep(freqlist{c},'freq','')); end
            freqsindir = sort(freqsindir); freqs2keep = find(freqsindir >= min(freqlim) & freqsindir <= max(freqlim));
            for c=1:numel(freqs2keep); plotFreq{c} = [filesep 'freq' num2str(freqsindir(freqs2keep(c)))]; end
        else % or just a single frequency
            plotFreq{1} = [filesep 'freq' num2str(freqlim)];
        end
    elseif strcmpi(plot_dim,'time_time') && ~freqfolder_contains_time_time
        % You can comment out the error line below if you are not fond of this type of error handling :-)
        error('You specified cfg.plot_dim = ''time_time'', but time_time is not available in this folder.');
        disp('WARNING: You specified cfg.plot_dim = ''time_time'', but time_time is not available in this folder. Defaulting to cfg.plot_dim = ''freq_time''');
        plot_dim = 'freq_time';
        plotFreq{1} = [filesep 'allfreqs'];
    end
else
    plotFreq = {''};
    freqlim = [];
end

% get filenames
if exist([folder_name filesep channelpool plotFreq{1} filesep 'grouptrain'],'dir')
    % grouptrain already exists, read from there
    allfiles = dir([folder_name filesep channelpool plotFreq{1} filesep 'grouptrain' filesep '*.mat']);
else
    % otherwise read from root
    allfiles = dir([folder_name filesep channelpool plotFreq{1} filesep '*.mat']);
end
allfiles = { allfiles(:).name };
allfiles(strncmp(allfiles,'.',1)) = []; % remove hidden files

% find unique subject filenames excluding the actual test name
allfiles = cellfun(@(x) regexprep(x,'CLASS_PERF_train_(\w*)_test_', ''), allfiles,'UniformOutput',false);
allfiles = cellfun(@(x) regexprep(x,'.mat', ''), allfiles,'UniformOutput',false);
subjectfiles = unique(allfiles);

% see if data exists
if isempty(subjectfiles)
    error(['could not find any unique subjects in specified folder ' folder_name filesep channelpool plotFreq{1} filesep ', maybe these data are not from a group training procedure?']);
else
    % if grouptrain folder did not exist, make and move files to folder grouptrain
    if ~exist([folder_name filesep channelpool plotFreq{1} filesep 'grouptrain'],'dir')
        mkdir([folder_name filesep channelpool plotFreq{1} filesep 'grouptrain']);
        movefile([folder_name filesep channelpool plotFreq{1} filesep 'CLASS_PERF*.mat'], [folder_name filesep channelpool plotFreq{1} filesep 'grouptrain']);
    end
end

% do the loop, restrict time and frequency if applicable
nSubj = numel(subjectfiles);
for cSubj = 1:nSubj
    fprintf(1,'loading subject %d of %d\n', cSubj, nSubj);

    % loop over frequencies (if no frequencies exist, it loads raw data)
    for cFreq = 1:numel(plotFreq)
        
        % determine what to load
        iterations = dir([folder_name filesep channelpool plotFreq{cFreq} filesep 'grouptrain' filesep '*' subjectfiles{cSubj} '*.mat']);
        iterations = { iterations(:).name };
        iterations(strncmp(iterations,'.',1)) = []; % remove hidden files
        
        % initialize subject
        notinitialized = true;
        itnr = 1;
        while notinitialized
            matObj = matfile([folder_name filesep channelpool plotFreq{cFreq} filesep 'grouptrain' filesep iterations{itnr}]);
            try
                BDM = matObj.BDM;
                notinitialized = false;
            catch
                disp(['cannot read ' folder_name filesep channelpool plotFreq{cFreq} filesep 'grouptrain' filesep iterations{itnr}]);
                itnr = itnr + 1;
            end
        end
        ClassOverTimeAv = zeros(size(BDM.ClassOverTime));
        WeightsOverTimeAv = zeros(size(BDM.WeightsOverTime));
        covPatternsOverTimeAv = zeros(size(BDM.covPatternsOverTime));
        corPatternsOverTimeAv = zeros(size(BDM.corPatternsOverTime));
        
        % Only BDM for now, will implement FEM later if useful
        % C2_averageAv = [];
        % C2_perconditionAv =[];
        
        nIts = 0;
        for cIt = 1:numel(iterations)
            fprintf(1,'.');
            if ~mod(cIt,80)
                fprintf(1,'\n');
            end
            
            % locate data
            matObj = matfile([folder_name filesep channelpool plotFreq{cFreq} filesep 'grouptrain' filesep iterations{cIt}]);
            
            % get data
            if ~isempty(whos(matObj,'BDM'))
                try
                    BDM = matObj.BDM;
                    % average data
                    ClassOverTimeAv = ClassOverTimeAv + BDM.ClassOverTime;
                    WeightsOverTimeAv = WeightsOverTimeAv + BDM.WeightsOverTime;
                    covPatternsOverTimeAv = covPatternsOverTimeAv + BDM.covPatternsOverTime;
                    corPatternsOverTimeAv = corPatternsOverTimeAv + BDM.corPatternsOverTime;
                    nIts = nIts + 1;
                catch 
                    disp(['cannot read ' folder_name filesep channelpool plotFreq{cFreq} filesep 'grouptrain' filesep iterations{cIt}]);
                end
                % confidence averaging not currently implemented, may do so later if useful

            elseif ~isempty(whos(matObj,'FEM'))
                FEM = [];
                % FEM averaging not currently implemented, may do so later if useful
            end
        end % end iterations loop
        fprintf(1,' successfully averaged %d of %d iterations for subject %d (%s) \n', nIts, nSubj-1, cSubj, subjectfiles{cSubj});
        clear BDM;
        % now compute the average for that subject / frequency
        BDM.ClassOverTime = ClassOverTimeAv/nIts;
        BDM.WeightsOverTime = WeightsOverTimeAv/nIts;
        BDM.covPatternsOverTime = covPatternsOverTimeAv/nIts;
        BDM.corPatternsOverTime = corPatternsOverTimeAv/nIts;
        BDM_CONF = []; % just remove
        settings = matObj.settings; % just copy over from the last one
        FEM = []; % just create an empty one
        clearvars *Av;
        % and save the result
        fprintf(1,'saving the average over iterations of subject %d of %d\n\n', cSubj, nSubj);
        fullfilename = [folder_name filesep channelpool plotFreq{cFreq} filesep subjectfiles{cSubj}];
        save(fullfilename,'FEM', 'BDM', 'BDM_CONF', 'settings', '-v7.3');
    end % end frequency loop
end % end subject loop

% remove folder
if ~keepfiles
    rmdir([folder_name filesep channelpool plotFreq{1} filesep 'grouptrain'],'s');
end

disp('done!');


function ndirs = drill2data(folder_name,channelpool)
% drills down until it finds the iterations folder, returns the number of directories it had to
% drill
notfound = true;
ndirs = 0;
while notfound
    dirz = dir(folder_name);
    dirz = {dirz([dirz(:).isdir]).name};
    nextlevel = dirz(cellfun(@isempty,strfind(dirz,'.')));
    if isempty(nextlevel)
        error('Cannot find data, select different location in the directory hierarchy and/or check path settings.');
    end
    if any(strcmpi(nextlevel,channelpool))
        folder_name = fullfile(folder_name,nextlevel{strcmpi(nextlevel,channelpool)});
    else
        folder_name = fullfile(folder_name,nextlevel{1});
    end
    ndirs = ndirs + 1;
    containsiterations = exist(fullfile(folder_name, 'grouptrain'),'dir') == 7 || ~isempty(dir(fullfile(folder_name, '*_train_*_test_*.mat')));
    containsfreq = ~isempty(dir(fullfile(folder_name, 'freq*'))) || ~isempty(dir(fullfile(folder_name, 'allfreqs')));
    if containsiterations || containsfreq
        notfound = false;
    end
end