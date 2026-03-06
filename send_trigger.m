function send_trigger(bit_index, duration_ms)
ioObj = io64(); %
status = io64(ioObj); %

if status ~= 0

    error('Failed to initialize io64.');

end

parallel_port_address = hex2dec('3FF8'); %

send_bit_pulse(ioObj, parallel_port_address, 0, 1000);

disp('ok')

function send_bit_pulse(ioObj, parallel_port_address, bit_index, duration_ms)

if bit_index < 0 || bit_index > 7

        error('bit_index must be between 0 and 7.');

end

bit_value = bitshift(1, bit_index);

io64(ioObj, parallel_port_address, bit_value);

pause(duration_ms / 1000);

io64(ioObj, parallel_port_address, 0);

end

end

