%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%
% process_chipod_script_AP.m
%
% ** this is currently a work-in-progress (AP). I am working on T-tide data
% right now to get it running and fix things. Eventually there will be a
% general script that can be applied to any cruise.**
%
% Script to do CTD-chipod processing.
%
% This script is part of CTD_Chipod software folder in the the mixingsoftware github repo.
% For latest version, download/sync the mixingsoftware github repo at
% https://github.com/OceanMixingGroup/mixingsoftware
%
% Before running:
% -This script assumes that CTD data has been processed into mat files and
% put into folders in some kind of standard form (with 'ctd_processing').
% -CTD data are used for two purposes: (1) the 24Hz data is used to compute
% dp/dt and compare with chipod acceleration to find the time offset . (2)
% lower resolution (here 1m) N^2 and dTdz are needed to compute chi.
% -Chipod data files need to be downloaded and saved as well.
%
% Instructions to run:
% 1) Copy this file and add your cruise name to the end of the filename.
% Note - I have tried to put *** where you need to change paths in file
% 2) Modify paths for your computer and cruise
% 3) Modify chipod info for your cruise
% 4) Run!
%
% OUTPUT:
% Saves a file for each cast and chipod with:
% avg
% ctd
% Writes a text file called 'Results.txt' that summarizes the settings used
% and the results (whether it found a chipod file, if it had good data etc.
% for each cast).
%
% Dependencies:
% get_profile_inds.m
% TimeOffset.m
% load_chipod_data
% get_T_calibration
% calibrate_chipod_dtdt
% get_chipod_chi
%
%
% Notes/Issues/Todo:
%
% - On some cruises a RBR is also deployed with the chipods that measures P
% and T. Might modfiy codes so that RBR data can be used in place of cTd
% data (though not in places where salinity is important?)
%
% - Sometimes chipod T calibration is bad. Does this affect chi?
%
% -As of 31 Mar 2015 , this runs for Ttide data. Still need to test for
%  other cruises.
%
% Started with 'process_chipod_script_june_ttide_V2.m' on 24 Mar 2015 and
% modified from there. A. Pickering - apickering@coas.oregonstate.edu
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%%

clear ; close all ; clc

tstart=tic;

%~~~~ Modify these paths for your cruise/computer ~~~~

% *** path for 'mixingsoftware' ***
mixpath='/Users/Andy/Cruises_Research/mixingsoftware/'

cd (fullfile(mixpath,'CTD_Chipod'))
addpath(fullfile(mixpath,'general')) % makelen.m in /general is needed
addpath(fullfile(mixpath,'marlcham')) % for integrate.m
addpath(fullfile(mixpath,'adcp')) % need for mergefields_jn.m in load_chipod_data

% *** Path where ctd data are located (already processed into mat files). There
% should be a folder within it called '24Hz'
CTD_path='/Users/Andy/Dropbox/TTIDE_OBSERVATIONS/scienceparty_share/TTIDE-RR1501/data/ctd_processed/'

% *** Path where chipod data are located
chi_data_path='/Users/Andy/Cruises_Research/Tasmania/Data/Chipod_CTD/'

% *** path where processed chipod data will be saved
chi_processed_path='/Users/Andy/Cruises_Research/Tasmania/Data/Chipod_CTD/Processed/';

% path to save figures to
fig_path=[chi_processed_path 'figures/'];
ChkMkDir(fig_path)
% ~~~~~~

% Make a list of all ctd files
% *** replace 'leg1' with name that is in your ctd files ***
CTD_list=dir([CTD_path  '24hz/' '*_leg1_*.mat']);

% make a text file to print a summary of results to
txtfname=['Results' datestr(floor(now)) '.txt'];

if exist(fullfile(chi_processed_path,txtfname),'file')
    delete(fullfile(chi_processed_path,txtfname))
end

fileID= fopen(fullfile(chi_processed_path,txtfname),'a');
fprintf(fileID,['Created ' datestr(now) '\n']);
fprintf(fileID,'CTD path \n');
fprintf(fileID,[CTD_path '\n']);
fprintf(fileID,'Chipod data path \n');
fprintf(fileID,[chi_data_path '\n']);
fprintf(fileID,'Chipod processed path \n');
fprintf(fileID,[chi_processed_path '\n']);
fprintf(fileID,'figure path \n');
fprintf(fileID,[fig_path '\n \n']);

fprintf(fileID,[' \n There are ' num2str(length(CTD_list)) ' CTD files' ])

% we loop through and do processing for each ctd file

hb=waitbar(0,'Looping through ctd files')

for a=5%1:length(CTD_list)
    
    waitbar(a/length(CTD_list),hb)
    
    clear castname tlim time_range cast_suffix_tmp cast_suffix CTD_24hz
    castname=CTD_list(a).name;
    
    fprintf(fileID,[' \n \n ~' castname ])
    
    %load CTD profile
    load([CTD_path '24hz/' castname])   
    % 24Hz data loaded here is in a structure 'data2'
    CTD_24hz=data2;clear data2
    % Sometimes the time needs to be converted from computer time into matlab (datenum?) time.
    % Time will be converted when CTD time is more than 5 years bigger than now.
    % JRM
    tlim=now+5*365;
    if CTD_24hz.time > tlim
        % jen didn't save us a real 24 hz time.... so create timeseries. JRM
        % from data record
        %disp('test!!!!!!!!!!')
        tmp=linspace(CTD_24hz.time(1),CTD_24hz.time(end),length(CTD_24hz.time));
        CTD_24hz.datenum=tmp'/24/3600+datenum([1970 1 1 0 0 0]);
    end
    
    clear tlim tmp
    time_range=[min(CTD_24hz.datenum) max(CTD_24hz.datenum)];
    
    % ** this might not work for other cruises/names ? - AP **
    cast_suffix_tmp=CTD_list(a).name; % Cast # may be different than file #. JRM
    cast_suffix=cast_suffix_tmp(end-8:end-6);
    
    % check if this is a towyo, if so skip for now
    clear splitlist
    splitlist=dir([CTD_path '*' cast_suffix '_split*.mat']);
    if size(splitlist,1)==0 % not a towyo, continue processing
        
        % load chipod info
        addpath /Users/Andy/Cruises_Research/Tasmania/
        Chipod_Deploy_Info_TTIDE
        
        %~~~ Enter Info for chipods deployed on CTD  ~~
        %~~~ This needs to be modified for each cruise ~~~
        
        for up_down_big=2%1:2
            
            % *** edit this info for your cruise/instruments ***
            short_labs={'up_1012','down_1013','1002','up_102','SN1010'};
            big_labs={'Ti UpLooker','Ti DownLooker','Unit 1002','Ti Downlooker','1010'};
            
            switch up_down_big
                case 1
                    whSN='SN1012'
                case 2
                    whSN='SN1013'
                case 3
                    whSN='SN1002' % this is a big chipod
                    whbig=1
                case 4
                    whSN='SN102'
                case 5
                    whSN='SN1010'
            end
            
            this_chi_info=ChiInfo.(whSN);
            clear chi_path az_correction suffix isbig cal is_downcast
            chi_path=fullfile(chi_data_path,this_chi_info.loggerSN);
            suffix=this_chi_info.suffix;
            isbig=this_chi_info.isbig;
            cal=this_chi_info.cal;
            
            fprintf(fileID,[ ' \n \n ' short_labs{up_down_big} ])
            
            d.time_range=datestr(time_range); % Time range of cast
            
            chi_processed_path_specific=fullfile(chi_processed_path,['chi_' short_labs{up_down_big} ])
            ChkMkDir(chi_processed_path_specific)
            
            fig_path_specific=fullfile(fig_path,['chi_' short_labs{up_down_big} ])
            ChkMkDir(fig_path_specific)
            
            % filename for processed chipod data (will check if already exists)
            processed_file=fullfile(chi_processed_path_specific,['cast_' cast_suffix '_' short_labs{up_down_big} '.mat']);
            
            %~~ Load chipod data
            if  0 % exist(processed_file,'file') %commented for now becasue some files were made but contain no data
                load(processed_file)
            else
                disp('loading chipod data')
                
                %~ For Ttide SN102, RTC on 102 was 5 hours 6mins behind for files 1-16?
                if strcmp(whSN,'SN102') && time_range(1)<datenum(2015,1,22,18,0,0)
                    % need to look at shifted time range
                    time_range_fix=time_range-(7/24)-(6/86400);
                    chidat=load_chipod_data(chi_path,time_range_fix,suffix,isbig);
                    % correct the time in chipod data
                    chidat.datenum=chidat.datenum+(7/24)+(6/86400);
                else
                    chidat=load_chipod_data(chi_path,time_range,suffix,isbig);
                end
                
                save(processed_file,'chidat')
                
            end
            
            %~ Moved this info here. For some chipods, this info changes
            % during deployment, so we will wire that in here for now...
            clear is_downcast az_correction
            
            
            %~ for T-tide SN1010, sensor was swapped and switched from up
            %to down at chipod file 25
            if strcmp(whSN,'SN1010')
                
                if chidat.datenum(1)>datenum(2015,1,25) % **check this, approximate **
                    % dowlooking
                    is_downcast=1;
                    az_correction=1;
                    this_chi_info.sensorSN='13-02D'
                else
                    % uplooking
                    is_downcast=0;
                    az_correction=-1;
                    this_chi_info.sensorSN='11-23D'
                end
                
            else
                is_downcast=this_chi_info.is_downcast;
                az_correction=this_chi_info.az_correction;
            end
            %~
            
            
            chidat.Info=this_chi_info;
            
            chidat.cal=this_chi_info.cal;
            
            if length(chidat.datenum)>1000

                [CTD_raw chidat]=AlignAndCalibrateChipodCTD(CTD_24hz,chidat,az_correction,cal,1)
                
            print('-dpng',[fig_path  'chi_' short_labs{up_down_big} '/cast_' cast_suffix '_w_TimeOffset'])
%                 % check if T calibration is ok

clear out2 err pvar
%                out2=interp1(chidat.datenum,chidat.cal.T1,CTD_24hz.datenum(ginds));
                out2=interp1(chidat.datenum,chidat.cal.T1,CTD_24hz.datenum);
                err=out2-CTD_24hz.t1;
                pvar=100* (1-(nanvar(err)/nanvar(CTD_24hz.t1)) );
                if pvar<50
                    disp('Warning T calibration not good')
                    fprintf(fileID,' *T calibration not good* ')
                end
                
                %
                ginds=1:length(CTD_24hz.p);
                do_timeseries_plot=1;
                if do_timeseries_plot
                    
                    xls=[min(CTD_24hz.datenum(ginds)) max(CTD_24hz.datenum(ginds))];
                    figure(2);clf
                    agutwocolumn(1)
                    wysiwyg
                    clf
                    
                    h(1)=subplot(411);
                    plot(CTD_24hz.datenum(ginds),CTD_24hz.t1(ginds))
                    hold on
                    plot(chidat.datenum,chidat.cal.T1)
                    plot(chidat.datenum,chidat.cal.T2-.5)
                    ylabel('T [\circ C]')
                    xlim(xls)
                    datetick('x')
                    title(['Cast ' cast_suffix ', ' short_labs{up_down_big} '  ' datestr(time_range(1),'dd-mmm-yyyy HH:MM') '-' datestr(time_range(2),15) ', ' CTD_list(a).name],'interpreter','none')
                    legend('CTD','chi','chi2-.5','location','best')
                    grid on
                    
                    h(2)=subplot(412);
                    plot(CTD_24hz.datenum(ginds),CTD_24hz.p(ginds));
                    ylabel('P [dB]')
                    xlim(xls)
                    datetick('x')
                    grid on
                    
                    h(3)=subplot(413);
                    plot(chidat.datenum,chidat.cal.T1P-.01)
                    hold on
                    plot(chidat.datenum,chidat.cal.T2P+.01)
                    ylabel('dT/dt [K/s]')
                    xlim(xls)
                    ylim(10*[-1 1])
                    datetick('x')
                    grid on
                    
                    h(4)=subplot(414);
                    plot(chidat.datenum,chidat.fspd)
                    ylabel('fallspeed [m/s]')
                    xlim(xls)
                    ylim(3*[-1 1])
                    datetick('x')
                    xlabel(['Time on ' datestr(time_range(1),'dd-mmm-yyyy')])
                    grid on
                    
                    linkaxes(h,'x');
                    orient tall
                    pause(.01)
                    
                    print('-dpng','-r300',[fig_path  'chi_' short_labs{up_down_big} '/cast_' cast_suffix '_T_P_dTdz_fspd.png']);
                end
                
                test_cal_coef=0;
                
                if test_cal_coef
                    ccal.coef1(a,1:5)=cal.coef.T1;
                    ccal.coef2(a,1:5)=cal.coef.T2;
                    figure(104)
                    plot(ccal.coef1),hold on,plot(ccal.coef2)
                end
                
                %%% now let's do the computation of chi..
                
                clear datad_1m datau_1m chi_inds p_max ind_max ctd
                % this gives us 1-m CTD data.
                if exist([CTD_path castname(1:end-6) '.mat'],'file')
                    load([CTD_path castname(1:end-6) '.mat']);
                    [p_max,ind_max]=max(chidat.cal.P);
                    if is_downcast
                        fallspeed_correction=-1;
                        ctd=datad_1m;
                        chi_inds=[1:ind_max];
                        sort_dir='descend';
                    else
                        fallspeed_correction=1;
                        ctd=datau_1m;
                        chi_inds=[ind_max:length(chidat.cal.P)];
                        sort_dir='ascend';
                    end
                    
                    % this plot for diagnostics to see if we are picking
                    % right half of profile (up/down)
                    %                     figure(99);clf
                    %                     plot(chidat.datenum,chidat.T1P)
                    %                     hold on
                    %                     plot(chidat.datenum(chi_inds),chidat.T1P(chi_inds))
                    
                    ctd.s1=interp_missing_data(ctd.s1,100);
                    ctd.t1=interp_missing_data(ctd.t1,100);
                    
                    % compute N^2 from 1m ctd data with 20 smoothing
                    smooth_len=20;
                    [bfrq] = sw_bfrq(ctd.s1,ctd.t1,ctd.p,nanmean(ctd.lat)); % JRM removed "vort,p_ave" from outputs
                    ctd.N2=abs(conv2(bfrq,ones(smooth_len,1)/smooth_len,'same')); % smooth once
                    ctd.N2=conv2(ctd.N2,ones(smooth_len,1)/smooth_len,'same'); % smooth twice
                    ctd.N2_20=ctd.N2([1:end end]);
                    
                    % compute dTdz from 1m ctd data with 20 smoothing
                    tmp1=sw_ptmp(ctd.s1,ctd.t1,ctd.p,1000);
                    ctd.dTdz=[0 ; abs(conv2(diff(tmp1),ones(smooth_len,1)/smooth_len,'same'))./diff(ctd.p)];
                    ctd.dTdz_20=conv2(ctd.dTdz,ones(smooth_len,1)/smooth_len,'same');
                    
                    % compute N^2 from 1m ctd data with 50 smoothing
                    smooth_len=50;
                    [bfrq] = sw_bfrq(ctd.s1,ctd.t1,ctd.p,nanmean(ctd.lat)); %JRM removed "vort,p_ave" from outputs
                    ctd.N2=abs(conv2(bfrq,ones(smooth_len,1)/smooth_len,'same')); % smooth once
                    ctd.N2=conv2(ctd.N2,ones(smooth_len,1)/smooth_len,'same'); % smooth twice
                    ctd.N2_50=ctd.N2([1:end end]);
                    
                    % compute dTdz from 1m ctd data with 50 smoothing
                    tmp1=sw_ptmp(ctd.s1,ctd.t1,ctd.p,1000);
                    ctd.dTdz=[0 ; abs(conv2(diff(tmp1),ones(smooth_len,1)/smooth_len,'same'))./diff(ctd.p)];
                    ctd.dTdz_50=conv2(ctd.dTdz,ones(smooth_len,1)/smooth_len,'same');
                    
                    % pick max dTdz and N^2 from these two?
                    ctd.dTdz=max(ctd.dTdz_50,ctd.dTdz_20);
                    ctd.N2=max(ctd.N2_50,ctd.N2_20);
                    
                    %~~ plot N2 and dTdz
                    doplot=1;
                    if doplot
                        figure(3);clf
                        subplot(121)
                        h20= plot(log10(abs(ctd.N2_20)),ctd.p)
                        hold on
                        h50=plot(log10(abs(ctd.N2_50)),ctd.p)
                        hT=plot(log10(abs(ctd.N2)),ctd.p)
                        xlabel('log_{10}N^2'),ylabel('depth [m]')
                        title(castname,'interpreter','none')
                        grid on
                        axis ij
                        legend([h20 h50 hT],'20m','50m','largest','location','best')
                        
                        subplot(122)
                        plot(log10(abs(ctd.dTdz_20)),ctd.p)
                        hold on
                        plot(log10(abs(ctd.dTdz_50)),ctd.p)
                        plot(log10(abs(ctd.dTdz)),ctd.p)
                        xlabel('dTdz [^{o}Cm^{-1}]'),ylabel('depth [m]')
                        grid on
                        axis ij
                        
                        print('-dpng',[fig_path  'chi_' short_labs{up_down_big} '/cast_' cast_suffix '_N2_dTdz'])
                    end
                    
                    %~~~ now let's do the chi computations:
                    
                    % remove loops in CTD data
                    extra_z=2; % number of extra meters to get rid of due to CTD pressure loops.
                    wthresh = 0.4;
                    [datau2,bad_inds] = ctd_rmdepthloops(CTD_24hz,extra_z,wthresh);
                    tmp=ones(size(datau2.p));
                    tmp(bad_inds)=0;
                    chidat.cal.is_good_data=interp1(datau2.datenum,tmp,chidat.cal.datenum,'nearest');
                    %
                    
                    %%% Now we'll do the main looping through of the data.
                    clear avg
                    nfft=128;
                    todo_inds=chi_inds(1:nfft/2:(length(chi_inds)-nfft))';
                    %                plot(chidat.datenum(todo_inds),chidat.T1P(todo_inds))
                    tfields={'datenum','P','N2','dTdz','fspd','T','S','P','theta','sigma',...
                        'chi1','eps1','chi2','eps2','KT1','KT2','TP1var','TP2var'};
                    for n=1:length(tfields)
                        avg.(tfields{n})=NaN*ones(size(todo_inds));
                    end
                    avg.datenum=chidat.cal.datenum(todo_inds+(nfft/2)); % This is the mid-value of the bin
                    avg.P=chidat.cal.P(todo_inds+(nfft/2));
                    good_inds=find(~isnan(ctd.p));
                    avg.N2=interp1(ctd.p(good_inds),ctd.N2(good_inds),avg.P);
                    avg.dTdz=interp1(ctd.p(good_inds),ctd.dTdz(good_inds),avg.P);
                    avg.T=interp1(ctd.p(good_inds),ctd.t1(good_inds),avg.P);
                    avg.S=interp1(ctd.p(good_inds),ctd.s1(good_inds),avg.P);
                    
                    % note sw_visc not included in newer versions of sw?
                    %addpath  /Users/Andy/Cruises_Research/mixingsoftware/seawater
                    % avg.nu=sw_visc(avg.S,avg.T,avg.P);
                    avg.nu=sw_visc_ctdchi(avg.S,avg.T,avg.P);
                    
                    % avg.tdif=sw_tdif(avg.S,avg.T,avg.P);
                    avg.tdif=sw_tdif_ctdchi(avg.S,avg.T,avg.P);
                    
                    avg.samplerate=1./nanmedian(diff(chidat.cal.datenum))/24/3600;
                    
                    h = waitbar(0,['Computing chi for cast ' cast_suffix]);
                    for n=1:length(todo_inds)
                        clear inds
                        inds=todo_inds(n)-1+[1:nfft];
                        
                        if all(chidat.cal.is_good_data(inds)==1)
                            avg.fspd(n)=mean(chidat.cal.fspd(inds));
                            
                            [tp_power,freq]=fast_psd(chidat.cal.T1P(inds),nfft,avg.samplerate);
                            avg.TP1var(n)=sum(tp_power)*nanmean(diff(freq));
                            
                            if avg.TP1var(n)>1e-4
                                
                                % not sure what this is for...
                                fixit=0;
                                if fixit
                                    trans_fcn=0;
                                    trans_fcn1=0;
                                    thermistor_filter_order=2;
                                    thermistor_cutoff_frequency=32;
                                    analog_filter_order=4;
                                    analog_filter_freq=50;
                                    tp_power=invert_filt(freq,invert_filt(freq,tp_power,thermistor_filter_order, ...
                                        thermistor_cutoff_frequency),analog_filter_order,analog_filter_freq);
                                end
                                
                                [chi1,epsil1,k,spec,kk,speck,stats]=get_chipod_chi(freq,tp_power,abs(avg.fspd(n)),avg.nu(n),...
                                    avg.tdif(n),avg.dTdz(n),'nsqr',avg.N2(n));
                                
                                avg.chi1(n)=chi1(1);
                                avg.eps1(n)=epsil1(1);
                                avg.KT1(n)=0.5*chi1(1)/avg.dTdz(n)^2;
                                
                            else
                                %disp('fail2')
                            end
                        else
                            % disp('fail1')
                        end
                        
                        if ~mod(n,10)
                            waitbar(n/length(todo_inds),h);
                        end
                        
                    end
                    delete(h)
                    
                    %
                    %~~~ Plot profiles of chi, KT, and dTdz
                    figure(4);clf
                    agutwocolumn(1)
                    wysiwyg
                    ax = MySubplot(0.1, 0.03, 0.02, 0.06, 0.1, 0.07, 3,2);
                    
                    axes(ax(1))
                    plot(log10(abs(avg.dTdz)),avg.P),axis ij
                    grid on
                    axis tight
                    xlabel('log_{10}(avg dTdz)')
                    ylabel('Depth [m]')
                    title(['cast ' cast_suffix])
                    
                    axes(ax(2))
                    plot(log10(abs(avg.N2)),avg.P),axis ij
                    grid on
                    xlabel('log_{10}(avg N^2)')
                    axis tight
                    ytloff
                    title([short_labs{up_down_big}],'interpreter','none')
                    
                    axes(ax(3))
                    plot(chidat.cal.T1P(chi_inds),chidat.cal.P(chi_inds)),axis ij
                    grid on
                    xlabel('dT/dt')
                    axis tight
                    ytloff
                    
                    axes(ax(4))
                    plot(log10(avg.chi1),avg.P,'.'),axis ij
                    xlabel('log_{10}(avg chi)')
                    axis tight
                    grid on
                    ylabel('Depth [m]')
                    
                    axes(ax(5))
                    plot(log10(avg.KT1),avg.P,'.'),axis ij
                    axis tight
                    xlabel('log_{10}(avg Kt1)')
                    grid on
                    ytloff
                    
                    axes(ax(6))
                    plot(log10(avg.eps1),avg.P,'.'),axis ij
                    axis tight
                    xlabel('log_{10}(avg eps1)')
                    grid on
                    ytloff
                    
                    linkaxes(ax,'y')
                    
                    print('-dpng',[fig_path  'chi_' short_labs{up_down_big} '/cast_' cast_suffix '_chi_' short_labs{up_down_big} '_avg_chi_KT_dTdz'])
                    
                    %~~~
                    
                    avg.castname=castname;
                    ctd.castname=castname;
                    avg.MakeInfo=['Made ' datestr(now) ' w/ process_chipod_script_AP.m']
                    ctd.MakeInfo=['Made ' datestr(now) ' w/ process_chipod_script_AP.m']
                    
                    chi_processed_path_avg=fullfile(chi_processed_path_specific,'avg');
                    ChkMkDir(chi_processed_path_avg)
                    processed_file=fullfile(chi_processed_path_avg,['avg_' cast_suffix '_' short_labs{up_down_big} '.mat']);
                    save(processed_file,'avg','ctd')
                    
                    ngc=find(~isnan(avg.chi1));
                    if numel(ngc)>1
                        fprintf(fileID,'Chi computed ')
                    end
                    
                end % if we have binned ctd data
                
            else
                disp('no good chi data for this profile');
                fprintf(fileID,' No chi file found ')
            end % if we have good chipod data for this profile
            
        end % each chipod on rosette (up_down_big)
        
    else
        fprintf(fileID,' Cast is a towyo, skipping ')
    end % if not towyo
    
end % each CTD file

delete(hb)

telapse=toc(tstart)
fprintf(fileID,['\n Processing took ' num2str(telapse/60) ' mins to run'])

%
%%
