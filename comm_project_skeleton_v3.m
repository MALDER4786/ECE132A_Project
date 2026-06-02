%% ECE 132A — Digital Communications Systems Project (2026 revised)
%  Student Skeleton Code
%
%  Instructions:
%    1. Place your team's data files in the same folder as this script:
%         rx_team_<TOKEN>.mat
%         params_team_<TOKEN>.json
%         truth_team_<TOKEN>.txt
%    2. Set TEAM_TOKEN below to your assigned token.
%    3. Run sections in order. Sections marked TODO must be completed.
%    4. Submit this file renamed: <Last>_<First>_CommProject.m
%
%  IMPORTANT:
%    * Phase 2.5 includes a seeded BUG in the helper function
%      mmse_equalizer_starter — finding it and producing a fixed version is
%      part of the assignment. Do NOT just rewrite the function from scratch
%      without first identifying what the bug does.
%    * Your script must populate the variable `appendix_A` (table) at the end
%      with every numerical answer in your report. The grader's verification
%      script reads it and diffs against truth.

clear; clc; close all;

%% =========================================================
%  SECTION 0 — Load Your Team's Data
%  =========================================================

TEAM_TOKEN = 'ECE132A-2026-XXXX-XXXX';   % TODO: replace with your team token

mat_file    = sprintf('rx_team_%s.mat',     TEAM_TOKEN);
params_file = sprintf('params_team_%s.json', TEAM_TOKEN);
truth_file  = sprintf('truth_team_%s.txt',   TEAM_TOKEN);

assert(exist(mat_file,    'file') == 2, 'Missing data file: %s',   mat_file);
assert(exist(params_file, 'file') == 2, 'Missing params file: %s', params_file);
assert(exist(truth_file,  'file') == 2, 'Missing truth file: %s',  truth_file);

load(mat_file);                          % loads rx_signal, preamble_symbols, etc.
params = jsondecode(fileread(params_file));
truth_bits = load_truth_bits(truth_file);

fprintf('=== Team %s ===\n', TEAM_TOKEN);
fprintf('  Modulation:        %s (M=%d, %d bits/symbol)\n', ...
    params.modulation, params.M, params.bits_per_symbol);
fprintf('  Target BER:        %g\n', params.target_BER);
fprintf('  EbN0_target_dB:    %.2f dB\n', params.EbN0_target_dB);
fprintf('  rx_signal length:  %d samples\n', numel(rx_signal));
fprintf('  preamble length:   %d symbols\n', numel(preamble_symbols));

% Pre-allocate the Appendix A summary (filled in throughout the script)
appendix_A = init_appendix_A(TEAM_TOKEN, params);


%% =========================================================
%  PHASE 1 — Modulation Theory & AWGN Simulation
%  =========================================================

fprintf('\n--- Phase 1: Modulation Theory & AWGN BER ---\n');

EbN0_dB  = 0 : 15;
EbN0_lin = 10.^(EbN0_dB/10);

% --- 1a/1b: Theoretical BER for YOUR modulation ---
% TODO: Replace with the correct BER expression for params.modulation.
%       Hint: BPSK/QPSK use Q(sqrt(2*EbN0_lin)); 16-QAM uses the standard
%       nearest-neighbor approximation; 8-PSK uses the Q-function form
%       with the appropriate distance ratio.
BER_theory = nan(size(EbN0_dB));         % TODO: replace

% --- 1b: Monte Carlo simulation ---
BER_sim = nan(size(EbN0_dB));            % TODO: fill in
% TODO: For each EbN0 value: generate random bits, modulate using
%       constellation_table_student(params.modulation), add complex AWGN,
%       perform minimum-distance detection, count bit errors. Use
%       at least 1e6 bits or until >= 100 errors per SNR point.

% --- Phase 1 Plot ---
figure('Name', 'Phase 1 — BER vs Eb/N0');
semilogy(EbN0_dB, BER_theory, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Theory'); hold on;
semilogy(EbN0_dB, BER_sim,    'ro', 'MarkerSize', 6,   'DisplayName', 'Simulation');
grid on; xlabel('E_b/N_0 (dB)'); ylabel('BER');
title(sprintf('Phase 1 — %s in AWGN (%s)', params.modulation, TEAM_TOKEN));
legend('Location', 'southwest'); ylim([1e-6, 1]);
set(gcf, 'PaperPositionMode', 'auto');


%% =========================================================
%  PHASE 2 — Matched Filtering & Eye Diagrams
%  =========================================================

fprintf('\n--- Phase 2: Matched Filter & Eye Diagrams ---\n');

sps     = params.samples_per_symbol;
rolloff = params.rrc.rolloff;
span    = params.rrc.span_symbols;

% TODO 2a: Build the RRC matched filter and verify Nyquist property of the
%          cascade RRC * RRC (zeros at non-zero integer T).
rrc = rrc_pulse_student(span, sps, rolloff);
% TODO: numerically verify cascade has -30 dB or better suppression off-peak

% Apply matched filter to YOUR rx_signal
mf_output = conv(rx_signal, rrc, 'full');
group_delay = span * sps;                    % cascade group delay = 2 * span*sps/2

% --- 2b: Eye diagrams at three sampling instants ---
% TODO: Reshape mf_output into rows of length 2*sps starting at three different
%       offsets (correct, 20% early, 20% late) and plot. Quantify peak-to-peak
%       eye opening at the optimal sample.

eye_correct = nan;     % TODO: peak-to-peak opening, dB rel. to symbol amplitude
eye_early   = nan;     % TODO
eye_late    = nan;     % TODO

% Symbol-rate samples used by all later phases:
sym_rate_samples = mf_output(group_delay + 1 : sps : end);

%% =========================================================
%  PHASE 2.5 — Channel Estimation & Equalization
%  =========================================================

fprintf('\n--- Phase 2.5: Channel Estimation & Equalization ---\n');

% --- 2.5b: LS channel estimation from preamble ---
N_pre  = params.preamble_length;
L_est  = 8;
pre_rx = sym_rate_samples(1:N_pre);

% Build the LS Toeplitz matrix A and observation vector b:
%   pre_rx[t + L_est - 1] = sum_i h[i] * preamble[t + L_est - 1 - i]
A = zeros(N_pre - L_est + 1, L_est);
for i = 0 : L_est - 1
    A(:, i + 1) = preamble_symbols(L_est - i : N_pre - i).';
end
b = pre_rx(L_est : N_pre).';

h_est = A \ b;                              % LS channel estimate
LS_residual_norm = norm(A * h_est - b);
sigma2_est = (LS_residual_norm^2) / (size(A,1) - L_est);

fprintf('  L_est = %d, ||Ah - b|| = %.4f, sigma^2_est = %.4f\n', ...
    L_est, LS_residual_norm, sigma2_est);

% Spectral analysis of estimated channel:
N_fft = 4096;
H_freq = fft(h_est, N_fft);
freq_norm = (0 : N_fft - 1) / N_fft;
[null_depth_lin, null_idx] = min(abs(H_freq(1 : N_fft/2)));
null_freq = freq_norm(null_idx);
null_depth_dB = 20 * log10(null_depth_lin + 1e-12);
fprintf('  Null at f = %.4f, depth = %.2f dB\n', null_freq, null_depth_dB);

% --- 2.5c: ZF and MMSE equalizers (length N_eq = 21) ---
N_eq = 21;
H_mat = build_channel_convmtx(h_est, N_eq);
delay = floor((N_eq + L_est - 1) / 2);
e_d = zeros(N_eq + L_est - 1, 1); e_d(delay + 1) = 1;

% Zero-forcing (no regularization)
w_zf = (H_mat' * H_mat) \ (H_mat' * e_d);

% MMSE: use the (buggy) starter, then your fixed version.
w_mmse_buggy = mmse_equalizer_starter(h_est, sigma2_est, N_eq, delay);
% TODO 2.5d: Identify the bug in mmse_equalizer_starter (below) and write
%            mmse_equalizer_fixed. Show SNR for both on YOUR data.
w_mmse_fixed = mmse_equalizer_fixed(h_est, sigma2_est, N_eq, delay);

% Apply equalizers to symbol-rate samples
eq_zf       = conv(sym_rate_samples, w_zf,         'full');
eq_buggy    = conv(sym_rate_samples, w_mmse_buggy, 'full');
eq_fixed    = conv(sym_rate_samples, w_mmse_fixed, 'full');

% Slicer-input SNR estimation: use the equalizer output on the preamble, where
% you know the true symbol values, and compute (signal power) / (residual power).
SNR_zf_dB    = slicer_snr(eq_zf,    delay, preamble_symbols);
SNR_buggy_dB = slicer_snr(eq_buggy, delay, preamble_symbols);
SNR_fixed_dB = slicer_snr(eq_fixed, delay, preamble_symbols);
fprintf('  ZF slicer SNR:           %.2f dB\n', SNR_zf_dB);
fprintf('  MMSE (buggy) slicer SNR: %.2f dB\n', SNR_buggy_dB);
fprintf('  MMSE (fixed) slicer SNR: %.2f dB\n', SNR_fixed_dB);

% Record Appendix A entries
appendix_A = put(appendix_A, 'channel_taps_estimated', h_est);
appendix_A = put(appendix_A, 'null_freq',              null_freq);
appendix_A = put(appendix_A, 'null_depth_dB',          null_depth_dB);
appendix_A = put(appendix_A, 'sigma2_estimated',       sigma2_est);
appendix_A = put(appendix_A, 'ZF_SNR_dB',              SNR_zf_dB);
appendix_A = put(appendix_A, 'MMSE_SNR_dB',            SNR_fixed_dB);
appendix_A = put(appendix_A, 'MMSE_minus_ZF_dB',       SNR_fixed_dB - SNR_zf_dB);
appendix_A = put(appendix_A, 'mmse_bug_explanation', ...
    '<TODO: one-sentence explanation of the bug in mmse_equalizer_starter>');


%% =========================================================
%  PHASE 3 — Fading Channels
%  =========================================================

fprintf('\n--- Phase 3: Fading Channels ---\n');

% Pick K from your team token: hex digit at the end mod 8 + 1
last_hex = TEAM_TOKEN(end);
if isstrprop(last_hex, 'digit'),     K_int = str2double(last_hex);
elseif isstrprop(last_hex, 'alpha'), K_int = double(upper(last_hex)) - double('A') + 10;
else,                                 K_int = 5;   % fallback
end
Rician_K = mod(K_int, 8) + 1;
fprintf('  Rician K = %d\n', Rician_K);

EbN0_fad_dB  = 0 : 2 : 30;
EbN0_fad_lin = 10.^(EbN0_fad_dB / 10);
% TODO: Simulate AWGN, Rayleigh, Rician (with your K) BER for BPSK.
%       Use the Rayleigh closed-form to verify, then report the fading
%       penalty at BER = 1e-3 and the SNR at which Rician matches AWGN to
%       within 1 dB.

BER_AWGN_3   = nan(size(EbN0_fad_dB));
BER_Rayleigh = nan(size(EbN0_fad_dB));
BER_Rician   = nan(size(EbN0_fad_dB));

BER_Rayleigh_theory = 0.5 * (1 - sqrt(EbN0_fad_lin ./ (1 + EbN0_fad_lin)));

figure('Name', 'Phase 3 — Fading BER');
semilogy(EbN0_fad_dB, BER_AWGN_3,           'k-',  'LineWidth', 1.5, 'DisplayName', 'AWGN'); hold on;
semilogy(EbN0_fad_dB, BER_Rayleigh_theory,  'b--', 'LineWidth', 1.5, 'DisplayName', 'Rayleigh theory');
semilogy(EbN0_fad_dB, BER_Rayleigh,         'bo',  'MarkerSize', 6,  'DisplayName', 'Rayleigh sim');
semilogy(EbN0_fad_dB, BER_Rician,           'rs',  'MarkerSize', 6,  'DisplayName', sprintf('Rician K=%d sim', Rician_K));
grid on; xlabel('E_b/N_0 (dB)'); ylabel('BER');
title(sprintf('Phase 3 — Fading BER (K=%d)', Rician_K));
legend('Location', 'southwest'); ylim([1e-5, 1]);
set(gcf, 'PaperPositionMode', 'auto');

fading_penalty_dB     = nan;   % TODO: at BER = 1e-3
Rician_AWGN_match_dB  = nan;   % TODO: SNR at which Rician matches AWGN within 1 dB

appendix_A = put(appendix_A, 'fading_penalty_dB',     fading_penalty_dB);
appendix_A = put(appendix_A, 'Rician_K_used',         Rician_K);


%% =========================================================
%  PHASE 5 — End-to-End Recovery
%  =========================================================

fprintf('\n--- Phase 5: End-to-End on Your Data ---\n');

% --- 5a: Identify the team-specific anomaly ---
% TODO: from preamble samples (sym_rate_samples(1:N_pre)) and their relationship
%       to the known preamble_symbols, decide which of:
%           'none', 'CFO', 'DC_bias', 'timing_offset'
%       applies to your data, estimate its value, and compensate for it
%       BEFORE channel estimation in your final pipeline.
%
%       Hints:
%         * DC_bias:       mean(preamble samples) is non-zero
%         * CFO:           phase of preamble samples drifts linearly across time
%         * timing_offset: matched-filter peak is at a fractional sample offset
%                          (interpolation needed)
%         * none:          preamble samples are well-explained by a static
%                          channel and Gaussian noise

anomaly_type  = 'none';   % TODO
anomaly_value = 0;        % TODO

% --- 5b: Run end-to-end pipeline with anomaly compensation ---
% (Re-do channel estimation and equalization AFTER compensating; this script
% currently uses the uncompensated estimate. Update before submitting.)
payload_eq = eq_fixed(N_pre + 1 : end);

table_const = constellation_table_student(params.modulation);
bps = params.bits_per_symbol;

% Number of payload symbols you should detect (no channel coding this year):
n_payload_syms = ceil(params.payload_length_bits / bps);
payload_eq = payload_eq(1 : n_payload_syms);

% Min-distance detection
[~, sym_idx] = min(abs(payload_eq(:) - table_const(:).'), [], 2);
sym_idx = sym_idx - 1;
det_bits = zeros(n_payload_syms, bps);
for k = 0 : bps - 1
    det_bits(:, bps - k) = bitand(sym_idx, 1);
    sym_idx = floor(sym_idx / 2);
end
det_bits = reshape(det_bits.', 1, []);
det_bits = det_bits(1 : params.payload_length_bits);

% BER vs truth
BER_meas = mean(det_bits ~= truth_bits);
fprintf('  measured BER: %.3e\n', BER_meas);

% --- 5c: Hidden message search ---
% Bytes 64..(64+11) = transmitted bits 512..(512+95)
candidate = det_bits(513 : 513 + 95);
hidden = bits_to_ascii(candidate);
fprintf('  candidate hidden message (first 12 chars): "%s"\n', hidden(1:min(12,end)));
% TODO: decide whether the candidate is printable ASCII (length>=8) and report.
hidden_message = 'none';

appendix_A = put(appendix_A, 'anomaly_type',  anomaly_type);
appendix_A = put(appendix_A, 'anomaly_value', anomaly_value);
appendix_A = put(appendix_A, 'measured_BER',  BER_meas);
appendix_A = put(appendix_A, 'hidden_message', hidden_message);



%% =========================================================
%  WRITE APPENDIX A CSV
%  =========================================================

csv_path = sprintf('%s_AppendixA.csv', strrep(TEAM_TOKEN, '-', '_'));
write_appendix_A(appendix_A, csv_path);
fprintf('\nWrote Appendix A summary to %s\n', csv_path);
fprintf('=== Done. Verify all numerical answers in your report match this file. ===\n');


%% =========================================================
%  HELPER FUNCTIONS
%  =========================================================

function bits = load_truth_bits(path)
    txt = fileread(path);
    lines = strsplit(strtrim(txt), newline);
    lines = lines(~startsWith(lines, '#'));
    bits = cellfun(@(s) str2double(strtrim(s)), lines);
    bits = bits(~isnan(bits));
end

function p = rrc_pulse_student(span, sps, alpha)
    n = -span*sps/2 : span*sps/2;
    t = n / sps;
    p = zeros(size(t));
    eps_ = 1e-12;
    for i = 1:numel(t)
        ti = t(i);
        if abs(ti) < eps_
            p(i) = 1 + alpha*(4/pi - 1);
        elseif abs(abs(4*alpha*ti) - 1) < eps_
            p(i) = (alpha/sqrt(2)) * ((1+2/pi)*sin(pi/(4*alpha)) + (1-2/pi)*cos(pi/(4*alpha)));
        else
            num = sin(pi*ti*(1-alpha)) + 4*alpha*ti*cos(pi*ti*(1+alpha));
            den = pi*ti*(1 - (4*alpha*ti)^2);
            p(i) = num/den;
        end
    end
    p = p / sqrt(sum(p.^2));
end

function H = build_channel_convmtx(h, N_eq)
    L = numel(h);
    H = zeros(N_eq + L - 1, N_eq);
    for col = 1:N_eq
        H(col : col + L - 1, col) = h(:);
    end
end

% ── BUGGY MMSE STARTER (Phase 2.5d) ────────────────────────────────────────
% The following starter contains ONE INTENTIONAL SIGN ERROR in the
% regularization term. Find it, explain it, and submit a corrected version
% as mmse_equalizer_fixed below. Do not just rewrite from scratch — first
% identify what the bug DOES (e.g., does it make the equalizer behave like
% ZF? Like a noise amplifier? At what SNR is the damage worst?)
function w = mmse_equalizer_starter(h, sigma2, N_eq, delay)
    L = numel(h);
    H = zeros(N_eq + L - 1, N_eq);
    for col = 1:N_eq
        H(col:col+L-1, col) = h(:);
    end
    e = zeros(N_eq + L - 1, 1); e(delay + 1) = 1;
    % --- BUG IS ON THE NEXT LINE ---
    w = (H' * H - sigma2 * eye(N_eq)) \ (H' * e);
end

% TODO: Provide the corrected version.
function w = mmse_equalizer_fixed(h, sigma2, N_eq, delay)
    % Replace the implementation below with your corrected version.
    w = mmse_equalizer_starter(h, sigma2, N_eq, delay);   % TODO: fix
end

function snr_dB = slicer_snr(eq_out, delay, preamble_symbols)
    % Estimate slicer-input SNR using the preamble portion of eq_out.
    N_pre = numel(preamble_symbols);
    aligned = eq_out(delay + 1 : delay + N_pre);
    aligned = aligned(:);
    p = preamble_symbols(:);
    e = aligned - p;
    sig_pwr   = mean(abs(p).^2);
    noise_pwr = mean(abs(e).^2);
    snr_dB = 10 * log10(sig_pwr / max(noise_pwr, eps));
end

function table = constellation_table_student(modulation)
    switch modulation
        case 'BPSK'
            table = [1 + 0j, -1 + 0j];
        case 'QPSK'
            gray = bitxor(0:3, floor((0:3)/2));
            table = zeros(1, 4);
            for idx = 0:3
                table(gray(idx+1)+1) = exp(1j*2*pi*idx/4);
            end
        case '8PSK'
            gray = bitxor(0:7, floor((0:7)/2));
            table = zeros(1, 8);
            for idx = 0:7
                table(gray(idx+1)+1) = exp(1j*2*pi*idx/8);
            end
        case {'16QAM','64QAM'}
            if strcmp(modulation,'16QAM'), M = 16; else, M = 64; end
            side = sqrt(M); bps_axis = log2(side);
            pam = (2*(0:side-1) - (side-1));
            gray = bitxor(0:side-1, floor((0:side-1)/2));
            pam_gray = zeros(1,side);
            for idx = 0:side-1, pam_gray(gray(idx+1)+1) = pam(idx+1); end
            syms = zeros(side,side);
            for ii = 1:side
                for qq = 1:side
                    syms(ii,qq) = pam_gray(ii) + 1j*pam_gray(qq);
                end
            end
            syms = syms / sqrt(mean(abs(syms(:)).^2));
            table = zeros(1, M);
            for ii = 0:side-1
                for qq = 0:side-1
                    table(bitshift(ii,bps_axis)+qq+1) = syms(ii+1,qq+1);
                end
            end
    end
end

function s = bits_to_ascii(bits)
    bits = bits(:).';
    n = floor(numel(bits) / 8);
    bytes = zeros(1, n, 'uint8');
    for i = 1 : n
        byte = bits((i-1)*8 + 1 : i*8);
        bytes(i) = uint8(sum(byte .* (2 .^ (7:-1:0))));
    end
    s = char(bytes);
end

function ap = init_appendix_A(token, params)
    ap.field = {'team_token'; 'modulation'; 'target_BER'; 'EbN0_target_dB'};
    ap.value = {token; params.modulation;
                params.target_BER; params.EbN0_target_dB};
end

function ap = put(ap, field, value)
    ap.field{end+1, 1} = field;
    if isnumeric(value) && ~isscalar(value)
        ap.value{end+1, 1} = mat2str(value, 6);
    elseif ischar(value)
        ap.value{end+1, 1} = value;
    else
        ap.value{end+1, 1} = value;
    end
end

function write_appendix_A(ap, path)
    fid = fopen(path, 'w');
    fprintf(fid, 'field,value\n');
    for i = 1 : numel(ap.field)
        v = ap.value{i};
        if isnumeric(v) && isscalar(v)
            fprintf(fid, '%s,%.6g\n', ap.field{i}, v);
        elseif ischar(v)
            fprintf(fid, '%s,"%s"\n', ap.field{i}, v);
        else
            fprintf(fid, '%s,"%s"\n', ap.field{i}, mat2str(v, 6));
        end
    end
    fclose(fid);
end
