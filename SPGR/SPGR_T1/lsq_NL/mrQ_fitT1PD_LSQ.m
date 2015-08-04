function [T1 PD resNorm] = mrQ_fitT1PD_LSQ(s,brainMask,tr,flipAngles,M0, ...
                                t1,Gain,B1,outDir,xform,mrQ,savenow)
%[T1 PD resNorm] = mrQ_fitT1PD_LSQ(s,brainMask,tr,flipAngles,M0, ...
%                                t1,Gain,B1,outDir,xform,mrQ,savenow)
%
% This function calls other functions that will perform the LSQ (least
% squares) fitting of T1 and PD. It will go much faster with the SunGrid
% Engine.
%
% INPUTS:
%       s           - Contains aligned data
%       brainMask   - Tissue mask delineating the brain region
%       tr          - TR taken from the S2 structure of aligned data
%       flipAngles  - Array of flipAngles for each scan.
%       M0          - M0 map
%       t1          - T1 data
%       Gain        -
%       B1          -
%       outDir      - Output directory where the resulting NIfTI files will
%                     be saved.
%       xform       - Transform
%       SGE         - Option to run using SGE [default = 0]
%       savenow     - Saves the outputs to disk [default = 0]
%       sub         - Subject name for SGE call
%
%
% OUTPUTS:
%       B1
%       resNorm
%       PD
%
%
% WEB RESOURCES
%       http://white.stanford.edu/newlm/index.php/Quantitative_Imaging
%
% See Also:
%       mrQfit_T1M0_ver2.m and mrQ_fitT1PD_SGE.m
%
%
% (C) Mezer lab, the Hebrew University of Jerusalem, Israel
%   2015
%
%

%% I. Check inputs
% 29.7.2015 commented the following input checks and added different checks
% if (~exist('sb','var')|| isempty(sb)),
%     sb='UN';
% end
%
% sgename=[sb 'T1PD'];
%
% if (~exist('SGE','var')|| isempty(SGE)),
%     SGE=0;
% end
% if (~exist('proclass','var')|| isempty(proclass))
%     proclass=0;
% end

if (~exist('savenow','var')|| isempty(savenow)),
    savenow=0;
end
if isfield(mrQ,'SunGrid')
    SGE=mrQ.SunGrid;
else
    SGE=0;
end

if isfield(mrQ,'sub')
    sb=mrQ.sub;
else
    sb='UN';
end
sgename=[sb 'T1PD'];

fullID=sb(isstrprop(sb, 'digit'));
id=str2double(fullID(1:8));
outDir=mrQ.spgr_initDir;


%% II. Set options for optimization procedure
a=version('-date');
if str2num(a(end-3:end))==2012 || str2num(a(end-3:end))==2015
    options = optimset('Algorithm', 'levenberg-marquardt','Display', 'off','Tolx',1e-12);
else
    options =  optimset('LevenbergMarquardt','on','Display', 'off','Tolx',1e-12);%'TolF',1e-12
    
end
% We put all the relevant data in a structure called "opt". 
% This will make it  easier to send it between the computers in the grid
sz=size(brainMask);
for i=1:length(s)
    tmp=s(i).imData(brainMask);
    opt.s(:,i)=double(tmp);
end

opt.flipAngles = double(flipAngles);
opt.tr = double(tr);

opt.x0(:,1) = double(M0(brainMask));%./Gain(brainMask));
opt.x0(:,2) = double(t1(brainMask))*1000;

opt.wh   = find(brainMask);
opt.Gain = double(Gain(brainMask));
opt.B1   = double(B1(brainMask));

opt.outDir = [outDir '/tmpSG'];
opt.lb     = [0 0];
opt.ub     = [inf 10000];
opt.name   = '/T1PDlsqVx';
jumpindex=2000;

% Save a logfile with all the options used during processing:
logname = [outDir '/fitT1LSQ.mat'];
opt.logname=logname;

% Save an information file we can load afterwards, if needed.
save(opt.logname,'opt');
%added this save of mrQ
mrQ.LSQoptname=logname;
save(mrQ.name,'mrQ');
%% III. Perform the optimization (optional: use SunGrid)

% USE THE SGE

clear brainMask tmp Res M0 options
if SGE==1;
    jumpindex=2000;
    if (~exist([outDir '/tmpSG'],'dir')), mkdir([outDir '/tmpSG']);
        % the result from the grid will be saved in a temporary directory
        for jobindex=1:ceil(length(opt.wh)/jumpindex)
            jobname=1000*str2double(fullID(1:3))+jobindex;
            command=sprintf('qsub -cwd -j y -b y -N joblsq_%g "matlab -nodisplay -r ''mrQ_fitT1PD_SGE(%f,%g,%g); exit'' >log"', jobname, id,jumpindex,jobindex);
            [stat,res]=  system(command);
            if ~mod(jobindex,100)
                fprintf('%g jobs out of %g have been submitted    \n',jobindex,ceil(length(opt.wh)/jumpindex))
            end
        end
        
        %         if proclass==1
        %             sgerun2('mrQ_fitT1PD_SGE(opt,2000,jobindex);',sgename,1,1:ceil(length(opt.wh)/jumpindex));
        %         else
        %             sgerun('mrQ_fitT1PD_SGE(opt,2000,jobindex);',sgename,1,1:ceil(length(opt.wh)/jumpindex));
        %         end
    else
        an1 = input( 'Unfinished SGE run found: Would you like to try and finish the existing SGE run? Press 1 if yes. To start over, press 0 ');
        
        % Continue existing SGE run from where we left it last time
        % we find the fit that are missing
        if an1==1
            reval=[];
            list=ls(opt.outDir);
            ch=[1:jumpindex:length(opt.wh)];
            k=0;
            for ii=1:length(ch),
                
                ex=['_' num2str(ch(ii)) '_'];
                if length(regexp(list, ex))==0,
                    k=k+1;
                    reval(k)=(ii);
                end
            end
            
            if length(find(reval))>0
                % clean the sge output dir and run the missing fit
                eval(['!rm -f ~/sgeoutput/*' sgename '*'])
                %                 if proclass==1
                a=num2str(ceil(rand(1)*10));
                %sgerun2('mrQ_fitT1PD_SGE(opt,2000,jobindex);',[sgename a],1,reval)
                for kk=1:length(reval)
                    %                         sgerun2('mrQ_fitT1PD_SGE(opt,2000,jobindex);',[sgename num2str(kk)],1,reval(kk)); % we run the missing oupput again
                    jobindex=reval(kk);
                    jobname=1000*str2double(fullID(1:3))+jobindex;
                    command=sprintf('qsub -cwd -j y -b y -N joblsq_%g "matlab -nodisplay -r ''mrQ_fitT1PD_SGE(%f,%g,%g); exit'' >log"', jobname, id,jumpindex,jobindex);
                    [stat,res]=  system(command);
                    if ~mod(kk,100)
                        fprintf('%g jobs out of %g have been submitted     \n',kk,length(reval));
                    end
                end
                
                %                 else
                %                     sgerun('mrQ_fitT1PD_SGE(opt,2000,jobindex);',sgename,1,reval);
                %                 end
            end
            list=ls(opt.outDir);
            
            % Restart the SGE processing from the beginning
        elseif an1==0
            t=pwd;
            cd (outDir)
            !rm -rf tmpSG
            cd (t);
            
            eval(['!rm -f ~/sgeoutput/*' sgename '*'])
            mkdir([outDir '/tmpSG']);
            for jobindex=1:ceil(length(opt.wh)/jumpindex)
                jobname=1000*str2double(fullID(1:3))+jobindex;
                command=sprintf('qsub -cwd -j y -b y -N joblsq_%g "matlab -nodisplay -r ''mrQ_fitT1PD_SGE(%f,%g,%g); exit'' >log"', jobname, id,jumpindex,jobindex);
                [stat,res]= system(command);
                if ~mod(jobindex,100)
                    fprintf('%g jobs out of %g have been submitted     \n',jobindex,ceil(length(opt.wh)/jumpindex))
                end
            end
            %             if proclass==1
            %                 sgerun2('mrQ_fitT1PD_SGE(opt,2000,jobindex);',sgename,1,1:ceil(length(opt.wh)/jumpindex));
            %             else
            %                 sgerun('mrQ_fitT1PD_SGE(opt,2000,jobindex);',sgename,1,1:ceil(length(opt.wh)/jumpindex));
            %             end
        else
            error;
        end
    end
    
%% IV. Build the data that was fitted by the SGE to T1 and M0 maps
    % This loop checks if all the outputs have been saved and waits until
    % they are all done
    StopAndSave=0;
    fNum=ceil(length(opt.wh)/jumpindex);
    tic
    while StopAndSave==0
        % List all the files that have been created from the call to the
        % grid
        
        list=ls(opt.outDir);
        % Check if all the files have been made.  If they are, then collect
        % all the nodes and move on.
        if length(regexp(list, '.mat'))==fNum,
            StopAndSave=1;
            
            % Loop over the nodes and collect the output
            for i=1:fNum
                st=1 +(i-1)*jumpindex;
                ed=st+jumpindex-1;
                
                if ed>length(opt.wh), ed=length(opt.wh);end
                
                name=[opt.outDir '/' opt.name '_' num2str(st) '_' num2str(ed) '.mat'];
                load (name);
                t11(st:ed)=res(2,:);
                pd1(st:ed)=res(1,:);
                resnorm1(st:ed)=resnorm;
                
            end
            % Once we have collected all the nodes we delete the temporary
            t=pwd;
            cd (outDir)
            !rm -r tmpSG
            cd (t);
            eval(['!rm -f ~/sgeoutput/*' sgename '*'])
            
            
        else
            jobname=fullID(1:3);
            qStatCommand    = [' qstat | grep -i  joblsq_' jobname];
            [status result] = system(qStatCommand);
            tt=toc;
            if (isempty(result) && tt>60)
                % Then there are no jobs running. We will need to re-run it.
                
                % We will re-run only the one we need
                reval=[];
                list=ls(opt.outDir);
                ch=[1:jumpindex:length(opt.wh)];
                k=0;
                for ii=1:length(ch),
                    
                    ex=['_' num2str(ch(ii)) '_'];
                    if length(regexp(list, ex))==0,
                        k=k+1;
                        reval(k)=(ii);
                    end
                end
                
                if length(find(reval))>0
                    % clean the sge output dir and run the missing fit
                    eval(['!rm -f ~/sgeoutput/*' sgename '*'])
                    %                     if proclass==1
                    
                    % sgerun2('mrQ_fitT1PD_SGE(opt,2000,jobindex);',[sgename 'redo'],1,reval); % we run the missing oupput again
                    
                    for kk=1:length(reval)
                        jobindex=reval(kk);
                        jobname=1000*str2double(fullID(1:3))+jobindex;
                        command=sprintf('qsub -cwd -j y -b y -N joblsq_%g "matlab -nodisplay -r ''mrQ_fitT1PD_SGE(%f,%g,%g); exit'' >log"', jobname, id,jumpindex,jobindex);
                        [stat,res]=   system(command);
                        if ~mod(kk,100)
                            fprintf('%g jobs out of %g have been submitted            \n',kk,length(reval));
                        end
                        %                             sgerun2('mrQ_fitT1PD_SGE(opt,2000,jobindex);',[sgename num2str(kk)],1,reval(kk)); % we run the missing oupput again
                    end
                    
                    %                     else
                    %                         sgerun('mrQ_fitT1PD_SGE(opt,2000,jobindex);',sgename,1,reval);
                    %                     end
                end
                
            else
                %  keep waiting
            end
            
            
            
            
            
        end
        
        
        
        
        
        % Record how much time has elapsed since the call to the grid.
        %             t = toc;
        %             % If too much time has elapsed then we recall the grid;
        %             if t > 86400% 24hours
        %                 reval=[]
        %                 ch=[1:jumpindex:length(opt.wh)]; %the nude filre name
        %                 k=0;
        %                 reval=[];
        %
        %                 for ii=1:length(ch),
        %
        %                     ex=['_' num2str(ch(ii)) '_'];
        %                     if length(regexp(list, ex))==0,
        %                         k=k+1;
        %                         reval(k)=(ii); % we make a list of the grid run that are not done yet
        %
        %                     end
        %                 end;
        %                 if length(find(reval))>0
        %                     eval(['!rm ~/sgeoutput/*' sgename '*']) % we delete all our relevant grid jobs
        %                     if proclass==1
        %
        %
        %                         for kk=1:length(reva)
        %                         sgerun2('mrQ_fitT1PD_SGE(opt,500,jobindex);',sgename,1,reval(kk),[],[],3000); % we run the missing oupput again
        %                         end
        %                     else
        %
        %                         sgerun('mrQ_fitT1PD_SGE(opt,500,jobindex);',sgename,1,reval,[],[],3000); % we run the missing oupput again
        %                     end
        %                     else
        %                         display('somting is wrong in SGE run')
        %                         error
        %                     end
        %                 end
        
    end
    
% NO SGE
% Using the local computer to fit T1 and PD
else
    
    fprintf('\n Fitting the T1 map locally, may be slow. SunGrid use can be much faster             \n');
    
    if (~exist([outDir '/tmpSG'],'dir')),
        mkdir([outDir '/tmpSG']);
        jobindex=1:ceil(length(opt.wh)/jumpindex);
    else
        jobindex=[];
        list=ls(opt.outDir);
        ch= 1:jumpindex:length(opt.wh) ;
        k=0;
        for ii=1:length(ch),
            
            ex=['_' num2str(ch(ii)) '_'];
            if length(regexp(list, ex))==0,
                k=k+1;
                jobindex(k)=(ii);
            end
        end
    end
    
    
    if ~isempty(jobindex)
        for i=jobindex
            mrQ_fitT1PD_SGE(id,2000,i);
        end
    end
    
    %Build the  T1 and M0 maps
    fNum=ceil(length(opt.wh)/jumpindex);
    % List all the files that have been created from the call to the
    % grid
    
    list=ls(opt.outDir);
    % Check if all the files have been made.  If they are, then collect
    % all the nodes and move on.
    
    % Loop over the nodes and collect the output
    for i=1:fNum
        st=1 +(i-1)*jumpindex;
        ed=st+jumpindex-1;
        
        if ed>length(opt.wh), ed=length(opt.wh);end
        
        name=[opt.outDir '/' opt.name '_' num2str(st) '_' num2str(ed) '.mat'];
        load (name);
        t11(st:ed)=res(2,:);
        pd1(st:ed)=res(1,:);
        resnorm1(st:ed)=resnorm;
        
    end
    % Once we have collected all the nodes we delete the temporary
    t=pwd;
    cd (outDir)
    !rm -r tmpSG
    cd (t);
    eval(['!rm -f ~/sgeoutput/*' sgename '*'])
    
    % Run the optimization without using the SGE
    %                 for i= 1:length(opt.wh)
    %
    %                     [res(:,i), resnorm(i)] = lsqnonlin(@(par) errT1PD(par,opt.flipAngles,opt.tr,opt.s(i,:),opt.Gain(i),opt.B1(i),1,[]),opt.x0(i,:),opt.lb,opt.ub,options);
    %
    %                 end
    %                t11(:)=res(:,2);
    %                pd1(st:ed)=res(:,1);
    
end

T1 = zeros(sz);
PD = T1; resNorm=PD;
T1(opt.wh) = t11(:)./1000;
PD(opt.wh) = pd1(:);
resNorm(opt.wh) = resnorm1(:);

%% V. Save out results

if savenow==1
    dtiWriteNiftiWrapper(single(T1), xform, fullfile(outDir,['T1_lsq_last.nii.gz']));
    dtiWriteNiftiWrapper(single(PD), xform, fullfile(outDir,['PD_lsq_last.nii.gz']));
    dtiWriteNiftiWrapper(single(resNorm), xform, fullfile(outDir,['lsqT1PDresnorm_last.nii.gz']));
end