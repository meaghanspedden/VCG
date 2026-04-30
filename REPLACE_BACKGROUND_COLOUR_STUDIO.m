% REPLACE_BACKGROUND
% Simple green screen replacement with a solid background colour.
% No cropping, no clipping, no beep detection — just chroma key the whole video.

%% ===== USER SETTINGS =====
ffmpeg   = '"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"';

inVideo  = "C:\Users\mspedden\OneDrive - University College London\Patrick.mp4";
outFile  = "C:\Users\mspedden\Videos\consent_info_BSL_summary_keyed.mp4";

% Background colour (hex). Examples:
%   "0xAABEDC"  periwinkle (your current studio default)
%   "0xFFFFFF"  white
%   "0x1A1A2E"  dark navy
%   "0xF5F5F0"  off-white / warm white
bgColor  = "0x5B8DB8";

% Green screen key settings (same as your studio script)
keyColor  = "0x00FF00";
sim       = 0.26;
blend     = 0.10;
blur      = 0.8;
erosionPx = 1;

% Output frame size — set to your video's actual resolution
vidW = 1920;
vidH = 1080;

fpsExpr = "25";

%% ===== BUILD AND RUN FFMPEG COMMAND =====

filterComplex = sprintf([ ...
    '[0:v]format=rgba,' ...
    'gblur=sigma=%.3f,' ...
    'chromakey=%s:%.3f:%.3f,' ...
    'split=2[ck][rgb];' ...
    '[ck]alphaextract,erosion=%d[alpha];' ...
    '[rgb][alpha]alphamerge[fg];' ...
    '[1:v][fg]overlay=shortest=1:eof_action=endall,format=yuv420p[v]'], ...
    blur, keyColor, sim, blend, erosionPx);

cmd = sprintf([ ...
    '%s -y -i "%s" ' ...
    '-f lavfi -i "color=c=%s:s=%dx%d:r=%s" ' ...
    '-filter_complex "%s" ' ...
    '-map "[v]" -map 0:a ' ...
    '-c:v libx264 -crf 18 -pix_fmt yuv420p ' ...
    '-c:a aac -b:a 192k -ac 2 ' ...
    '-shortest "%s"'], ...
    ffmpeg, inVideo, bgColor, vidW, vidH, fpsExpr, filterComplex, outFile);

fprintf("Running ffmpeg...\n%s\n\n", cmd);
rc = system(cmd);

if rc == 0
    fprintf("Done! Output: %s\n", outFile);
else
    error("FFmpeg failed. Check the command above for clues.");
end