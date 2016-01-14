%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%
% MakeCasts_CTDchipod_Template.m
%
% Find data for each cast, align and calibrate etc.. save files for each
% cast.
%
% *Next step in processing is DoChiCalc_Template.m
%
%---------------------
% 10/26/15 - A.Pickering - Initial coding
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%%

clear ; close all ; clc

this_script_name='ProcessCTDchipod_Template.m'

% start a timer
tstart=tic;

% *** path for 'mixingsoftware' ***
mixpath='/Users/Andy/Cruises_Research/mixingsoftware/';

% add paths we need
addpath(fullfile(mixpath,'CTD_Chipod'));
addpath(fullfile(mixpath,'CTD_Chipod','Templates'));
addpath(fullfile(mixpath,'general')); % makelen.m in /general is needed
addpath(fullfile(mixpath,'marlcham')); % for integrate.m
addpath(fullfile(mixpath,'adcp')); % need for mergefields_jn.m in load_chipod_data

% *** Load paths for CTD and chipod data
Load_chipod_paths_TestData

%*** Load chipod deployment info
Chipod_Deploy_Info_template
%
% Make a list of all ctd files
CTD_list=dir(fullfile(CTD_out_dir_24hz,['*' ChiInfo.CastString '*.mat*']));
disp(['There are ' num2str(length(CTD_list)) ' CTD casts to process in ' CTD_out_dir_24hz])
%
% make a text file to print a summary of results to
MakeResultsTextFile
%
% Loop through each ctd file
hb=waitbar(0,'Looping through ctd files');
for a=1:length(CTD_list)
    %
    close all
    clear castname tlim time_range cast_suffix_tmp cast_suffix CTD_24hz
    
    % update waitbar
    waitbar(a/length(CTD_list),hb)
    
    % CTD castname we are working with
    castname=CTD_list(a).name
    
    fprintf(fileID,[ '\n\n\n ~~~~~~~~~~~~~~~~~~~~' ]);
    fprintf(fileID,[' \n \n ~' castname ]);
    
    %load 24hz CTD profile
    load(fullfile(CTD_out_dir_24hz, castname))
    CTD_24hz=data2;clear data2
    CTD_24hz.ctd_file=castname;
    
    % Sometimes the 24hz ctd time needs to be converted from computer time into matlab (datenum?) time.
    tlim=now+5*365;
    if CTD_24hz.time > tlim
        tmp=linspace(CTD_24hz.time(1),CTD_24hz.time(end),length(CTD_24hz.time));
        CTD_24hz.datenum=tmp'/24/3600+datenum([1970 1 1 0 0 0]);
    end
    
    clear tlim tmp
    time_range=[min(CTD_24hz.datenum) max(CTD_24hz.datenum)];
    d.time_range=datestr(time_range); % Time range of CTD cast
    
    % regular file, just use cast # for name
    id1=strfind(castname,ChiInfo.CastString);
    cast_suffix=castname(id1+length(ChiInfo.CastString)+1 : id1+length(ChiInfo.CastString)+3)
    
    %-- For multiple chipods, would have loop here --
    for iSN=1%:length(ChiInfo.SNs)
        
        close all
        clear whSN this_chi_info chi_path az_correction suffix isbig cal is_downcast
        
        whSN=ChiInfo.SNs{iSN};
        this_chi_info=ChiInfo.(whSN);
        
        % full path to raw data for this chipod
        chi_path=fullfile(chi_data_path,this_chi_info.loggerSN);
        suffix=this_chi_info.suffix;
        isbig=this_chi_info.isbig;
        cal=this_chi_info.cal;
        
        fprintf(fileID,[ ' \n\n ---------' ]);
        fprintf(fileID,[ ' \n ' whSN ]);
        fprintf(fileID,[ ' \n ---------\n' ]);
        
        %~~ specific paths for this chipod
        chi_proc_path_specific=fullfile(chi_proc_path,[whSN]);
        ChkMkDir(chi_proc_path_specific)
        
        chi_fig_path_specific=fullfile(chi_proc_path_specific,'figures')
        ChkMkDir(chi_fig_path_specific)
        %~~
        
        % filename for processed chipod data (will check if already exists)
        processed_file=fullfile(chi_proc_path_specific,['cast_' cast_suffix '_' whSN '.mat'])
        
        %~~ Load chipod data
        if  1 %~exist(processed_file,'file')
            %load(processed_file)
            % else
            disp('loading chipod data')
            
            % find and load chipod data for this time range
            chidat=load_chipod_data(chi_path,time_range,suffix,isbig,1);
            ab=get(gcf,'Children');
            axes(ab(end));
            title([whSN ' - ' castname ' - Raw Data '],'interpreter','none')
            
            % save plot
            print('-dpng',fullfile(chi_fig_path_specific,[whSN '_cast_' cast_suffix '_Fig1_RawChipodTS']))
            
            chidat.time_range=time_range;
            chidat.castname=castname;
            
            savedir_cast=fullfile(chi_proc_path_specific,'cast')
            ChkMkDir(savedir_cast)
            save(fullfile(savedir_cast,['cast_' cast_suffix '_' whSN '.mat']),'chidat')
            
            % carry over chipod info
            chidat.Info=this_chi_info;
            chidat.cal=this_chi_info.cal;
            az_correction=this_chi_info.az_correction;
            
            if length(chidat.datenum)>1000
                
                % Align
                [CTD_24hz chidat]=AlignChipodCTD(CTD_24hz,chidat,az_correction,1);
                print('-dpng',fullfile(chi_fig_path_specific,[whSN '_cast_' cast_suffix '_Fig2_w_TimeOffset']))
                
                % zoom in and plot again
                xlim([nanmin(chidat.datenum) nanmin(chidat.datenum)+400/86400])
                print('-dpng',fullfile(chi_fig_path_specific,[whSN '_cast_' cast_suffix '_Fig3_w_TimeOffset_Zoom']))
                
                % Calibrate T and dT/dt
                [CTD_24hz chidat]=CalibrateChipodCTD(CTD_24hz,chidat,az_correction,1);
                print('-dpng',fullfile(chi_fig_path_specific,[whSN '_cast_' cast_suffix '_Fig4_dTdtSpectraCheck']))
                
                % save again, with time-offset and calibration added
                savedir_cal=fullfile(chi_proc_path_specific,'cal')
                ChkMkDir(savedir_cal)
                % processed_file=fullfile(chi_proc_path_specific,['cast_' cast_suffix '_' whSN '.mat'])
                save(fullfile(savedir_cal,['cast_' cast_suffix '_' whSN '.mat']),'chidat')
                
                % check if T1 calibration is ok
                clear out2 err pvar
                out2=interp1(chidat.datenum,chidat.cal.T1,CTD_24hz.datenum);
                err=out2-CTD_24hz.t1;
                pvar=100* (1-(nanvar(err)/nanvar(CTD_24hz.t1)) );
                if pvar<50
                    disp('Warning T calibration not good')
                    fprintf(fileID,' *T1 calibration not good* ');
                end
                
                if this_chi_info.isbig==1
                    % check if T2 calibration is ok
                    clear out2 err pvar
                    out2=interp1(chidat.datenum,chidat.cal.T2,CTD_24hz.datenum);
                    err=out2-CTD_24hz.t1;
                    pvar=100* (1-(nanvar(err)/nanvar(CTD_24hz.t1)) );
                    if pvar<50
                        disp('Warning T2 calibration not good')
                        fprintf(fileID,' *T2 calibration not good* ');
                    end
                end
                
                %~~~~
                do_timeseries_plot=1;
                if do_timeseries_plot
                    
                    h=ChiPodTimeseriesPlot(CTD_24hz,chidat)
                    axes(h(1))
                    title(['Cast ' cast_suffix ', ' whSN '  ' datestr(time_range(1),'dd-mmm-yyyy HH:MM') '-' datestr(time_range(2),15) ', ' CTD_list(a).name],'interpreter','none')
                    axes(h(end))
                    xlabel(['Time on ' datestr(time_range(1),'dd-mmm-yyyy')])
                    print('-dpng','-r300',fullfile(chi_fig_path_specific,[whSN '_cast_' cast_suffix '_Fig5_T_P_dTdz_fspd.png']));
                end
                %~~~~
                
                clear datad_1m datau_1m chi_inds p_max ind_max ctd
                
                id3=strfind(castname,'.mat')
                binned_name=castname(1:id3-3)
                
                if exist(fullfile(CTD_out_dir_bin,[ binned_name '.mat']),'file')
                    load(fullfile(CTD_out_dir_bin,[ binned_name '.mat']));
                    % find max p from chi (which is really just P from CTD)
                    [p_max,ind_max]=max(chidat.cal.P);
                    
                    %~ break up chi into down and up casts
                    
                    % upcast
                    chi_up=struct();
                    chi_up.datenum=chidat.cal.datenum(ind_max:length(chidat.cal.P));
                    chi_up.P=chidat.cal.P(ind_max:length(chidat.cal.P));
                    chi_up.T1P=chidat.cal.T1P(ind_max:length(chidat.cal.P));
                    chi_up.fspd=chidat.cal.fspd(ind_max:length(chidat.cal.P));
                    chi_up.castdir='up';
                    chi_up.Info=this_chi_info;
                    if this_chi_info.isbig
                        % 2nd sensor on 'big' chipods
                        chi_up.T2P=chidat.cal.T2P(ind_max:length(chidat.cal.P));
                    end
                    chi_up.ctd.bin=datau_1m;
                    chi_up.ctd.raw=CTD_24hz;
                    
                    % downcast
                    chi_dn=struct();
                    chi_dn.datenum=chidat.cal.datenum(1:ind_max);
                    chi_dn.P=chidat.cal.P(1:ind_max);
                    chi_dn.T1P=chidat.cal.T1P(1:ind_max);
                    chi_dn.fspd=chidat.cal.fspd(1:ind_max);
                    chi_dn.castdir='down';
                    chi_dn.Info=this_chi_info;
                    if this_chi_info.isbig
                        % 2nd sensor on 'big' chipods
                        chi_dn.T2P=chidat.cal.T2P(1:ind_max);
                    end
                    chi_dn.ctd.bin=datad_1m;
                    chi_dn.ctd.raw=CTD_24hz;
                    %~
                    
                    
                    %~~~
                    % save these data here now
                    clear fname_dn fname_up
                    fname_dn=fullfile(savedir_cal,['cast_' cast_suffix '_' whSN '_downcast.mat']);
                    % fname_dn=fullfile(chi_proc_path_specific,['cast_' cast_suffix '_' whSN '_downcast.mat']);
                    clear C;C=chi_dn;
                    save(fname_dn,'C')
                    %fname_up=fullfile(chi_proc_path_specific,['cast_' cast_suffix '_' whSN '_upcast.mat']);
                    fname_up=fullfile(savedir_cal,['cast_' cast_suffix '_' whSN '_upcast.mat']);
                    clear C;C=chi_up;
                    save(fname_up,'C')
                    clear C
                    %~~~
                    %
                    
                    
                end % if we have binned ctd data
                
            else
                disp('no good chi data for this profile');
                fprintf(fileID,' No chi file found ');
            end % if we have good chipod data for this profile
            
        else
            disp('this file already processed')
            fprintf(fileID,' file already exists, skipping ');
        end % already processed
        
    end % each chipod on rosette (up_down_big)
    
end % each CTD file

delete(hb)

telapse=toc(tstart)
fprintf(fileID,['\n \n Done! \n Processing took ' num2str(telapse/60) ' mins to run']);

%
%%