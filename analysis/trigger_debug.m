% Look at the first few triggers
disp('Video onsets (first 5):');
disp(videoOnsets(1:5));

disp('OPM triggers (first 5):');
disp(datTrigs(1:5));

fprintf('Video duration: %.2f s\n', videoOnsets(end)-videoOnsets(1));
fprintf('OPM triggers duration: %.2f s\n', datTrigs(end)-datTrigs(1));

dt_video = diff(videoOnsets_sync);   % time differences between consecutive video triggers
dt_opm   = diff(datTrigs);           % time differences between consecutive OPM triggers

% Basic stats
fprintf('Video: mean dt = %.3f s, std dt = %.3f s\n', mean(dt_video), std(dt_video));
fprintf('OPM:   mean dt = %.3f s, std dt = %.3f s\n', mean(dt_opm), std(dt_opm));


offset = datTrigs(1) - videoOnsets(1);

% Shift video onsets to align with OPM triggers
videoOnsets_sync = videoOnsets + offset;

fprintf('Time offset applied: %.3f s\n', offset);
%diff is about 71 seconds.

tol = 0.1; % 50 ms tolerance

% Find video triggers that have matching OPM triggers
matched = arrayfun(@(t) any(abs(datTrigs - t) <= tol), videoOnsets_sync);
missingIndices = find(~matched);

fprintf('Number of missing triggers: %d\n', length(missingIndices));
disp('Indices of video onsets without matching OPM trigger:');
disp(missingIndices);


figure; hold on;
plot(videoOnsets_sync, 1:length(videoOnsets_sync), 'bo-');
plot(datTrigs, 1:length(datTrigs), 'rx-');
plot(videoOnsets_sync(missingIndices), missingIndices, 'ko', 'MarkerSize',8,'LineWidth',2);
xlabel('Time (s)'); ylabel('Trigger index');
legend('Video','OPM','Missing');
title('Aligned triggers');

%%
figure;
plot(videoOnsets_sync, 1:length(videoOnsets_sync), 'bo-'); hold on;
plot(datTrigs, 1:length(datTrigs), 'rx-');
xlabel('Time (s)');
ylabel('Trigger index');
legend('Video','OPM');
title('Video vs OPM trigger times');
grid on;