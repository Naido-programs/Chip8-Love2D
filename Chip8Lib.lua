local lib = {}
math.randomseed(os.time())

local band   = bit.band
local bor    = bit.bor
local bxor   = bit.bxor
local rshift = bit.rshift
local lshift = bit.lshift

local DISPLAY = {}    -- display 64x32
local MEMORY  = {}    -- memory 4Kb (4096 bytes)
local PC = 0x200      -- program counter (base 0)
local I  = 0          -- 16-bit index REGISTER
local STACK = {}      -- 16-bit STACK
local DELAY_TIMER = 0 -- delay timer
local SOUND_TIMER = 0 -- sound timer
local REGISTER = {}   -- 16 8-bit REGISTERS (V0-VF)
local INSTRUCTION = 0 -- 16 bit instruction
local FIRST_BYTE  = 0
local SECOND_BYTE = 0
local INSTRUCTION_NUMBER = 0
local KEYPAD = {}
local SCANCODES = {"x","1","2","3","q","w","e","a","s","d","z","c","4","r","f","v"}
local FONT_INDEX = 0x50

local function clearDisplay()
    for y = 0, 31 do
        DISPLAY[y] = {}
        for x = 0, 63 do
            DISPLAY[y][x] = 0
        end
    end
end

local function byteToBin(byte)
    local t = {}
    for i = 7, 0, -1 do
        t[#t + 1] = band(rshift(byte, i), 0x1)
    end
    return t
end

function lib.updateTimers()
    if DELAY_TIMER > 0 then
        DELAY_TIMER = DELAY_TIMER - 1
    end
    if SOUND_TIMER > 0 then
        SOUND_TIMER = SOUND_TIMER - 1
    end
end

function lib.setKeypad(key, pressed)
    for i, v in ipairs(SCANCODES) do
        if v == key then
            KEYPAD[i-1] = pressed or false
            break
        end
    end
end

function lib.isKeyPressed(keyCode)
    return KEYPAD[keyCode] or false
end

function lib.getDisplay()
    return DISPLAY
end

function lib.loadROM(ROMPath)
    local fontTable = {
        0xF0,0x90,0x90,0x90,0xF0, -- 0
        0x20,0x60,0x20,0x20,0x70, -- 1
        0xF0,0x10,0xF0,0x80,0xF0, -- 2
        0xF0,0x10,0xF0,0x10,0xF0, -- 3
        0x90,0x90,0xF0,0x10,0x10, -- 4
        0xF0,0x80,0xF0,0x10,0xF0, -- 5
        0xF0,0x80,0xF0,0x90,0xF0, -- 6
        0xF0,0x10,0x20,0x40,0x40, -- 7
        0xF0,0x90,0xF0,0x90,0xF0, -- 8
        0xF0,0x90,0xF0,0x10,0xF0, -- 9
        0xF0,0x90,0xF0,0x90,0x90, -- A
        0xE0,0x90,0xE0,0x90,0xE0, -- B
        0xF0,0x80,0x80,0x80,0xF0, -- C
        0xE0,0x90,0x90,0x90,0xE0, -- D
        0xF0,0x80,0xF0,0x80,0xF0, -- E
        0xF0,0x80,0xF0,0x80,0x80  -- F
    }
    
    -- Initialize everything
    clearDisplay()
    for i = 0, 4095 do MEMORY[i] = 0 end
    for i = 0, 15 do REGISTER[i] = 0 end
    
    -- Load font at 0x50
    for i = 0, 79 do
        MEMORY[FONT_INDEX + i] = fontTable[i + 1]
    end
    
    -- Load ROM at 0x200
    local file = assert(io.open(ROMPath, "rb"))
    local allBytes = file:read("*all")
    file:close()
    
    for i = 1, #allBytes do
        MEMORY[0x200 + i - 1] = string.byte(allBytes, i)
    end
    
    PC = 0x200
    I = 0
    DELAY_TIMER = 0
    SOUND_TIMER = 0
    STACK = {}
    KEYPAD = {}
    for i = 0, 15 do
        KEYPAD[i] = false
    end
    
    print("FILE LOADED:", ROMPath, "SIZE:", #allBytes)
end

function lib.fetch()
    FIRST_BYTE = MEMORY[PC]
    SECOND_BYTE = MEMORY[PC + 1]
    INSTRUCTION = lshift(FIRST_BYTE, 8) + SECOND_BYTE
    INSTRUCTION_NUMBER = rshift(FIRST_BYTE, 4)
    x = band(FIRST_BYTE, 0x0F)
    y = rshift(SECOND_BYTE, 4)
    PC = PC + 2
end

function lib.decode(debug)
    debug = debug or false

    if INSTRUCTION_NUMBER == 0x0 then
        if INSTRUCTION == 0x00E0 then -- CLEAR
            clearDisplay()
            if debug then print("00E0 - CLEAR DISPLAY") end
            
        elseif INSTRUCTION == 0x00EE then -- RETURN
            PC = table.remove(STACK)
            if debug then print("00EE - RETURN to " .. PC) end
        end
        
    elseif INSTRUCTION_NUMBER == 0x1 then -- 1NNN: JUMP to NNN
        local address = band(INSTRUCTION, 0x0FFF)
        PC = address
        if debug then print("1NNN - JUMP to " .. address) end

    elseif INSTRUCTION_NUMBER == 0x2 then -- 2NNN: CALL subroutine at NNN
        local address = band(INSTRUCTION, 0x0FFF)
        table.insert(STACK, PC)
        PC = address
        if debug then print("2NNN - CALL " .. address) end

    elseif INSTRUCTION_NUMBER == 0x3 then -- 3XNN: Skip if VX == NN
        if REGISTER[x] == SECOND_BYTE then
            PC = PC + 2
        end
        if debug then print("3XNN - SKIP if V["..x.."] == "..SECOND_BYTE) end

    elseif INSTRUCTION_NUMBER == 0x4 then -- 4XNN: Skip if VX != NN
        if REGISTER[x] ~= SECOND_BYTE then
            PC = PC + 2
        end
        if debug then print("4XNN - SKIP if V["..x.."] != "..SECOND_BYTE) end

    elseif INSTRUCTION_NUMBER == 0x5 then -- 5XY0: Skip if VX == VY
        if band(INSTRUCTION, 0x000F) == 0 then
            if REGISTER[x] == REGISTER[y] then
                PC = PC + 2
            end
            if debug then print("5XY0 - SKIP if V["..x.."] == V["..y.."]") end
        end

    elseif INSTRUCTION_NUMBER == 0x6 then -- 6XNN: Set VX = NN
        REGISTER[x] = SECOND_BYTE
        if debug then print("6XNN - SET V["..x.."] = "..SECOND_BYTE) end

    elseif INSTRUCTION_NUMBER == 0x7 then -- 7XNN: Add NN to VX
        REGISTER[x] = band(REGISTER[x] + SECOND_BYTE, 0xFF)
        if debug then print("7XNN - ADD V["..x.."] += "..SECOND_BYTE) end

    elseif INSTRUCTION_NUMBER == 0x8 then
        local op = band(SECOND_BYTE, 0x0F)
        
        if op == 0x0 then -- 8XY0: VX = VY
            REGISTER[x] = REGISTER[y]
            if debug then print("8XY0 - V["..x.."] = V["..y.."]") end
            
        elseif op == 0x1 then -- 8XY1: VX = VX OR VY
            REGISTER[x] = bor(REGISTER[x], REGISTER[y])
            if debug then print("8XY1 - V["..x.."] OR V["..y.."]") end
            
        elseif op == 0x2 then -- 8XY2: VX = VX AND VY
            REGISTER[x] = band(REGISTER[x], REGISTER[y])
            if debug then print("8XY2 - V["..x.."] AND V["..y.."]") end
            
        elseif op == 0x3 then -- 8XY3: VX = VX XOR VY
            REGISTER[x] = bxor(REGISTER[x], REGISTER[y])
            if debug then print("8XY3 - V["..x.."] XOR V["..y.."]") end
            
        elseif op == 0x4 then -- 8XY4: VX = VX + VY, set VF on carry
            local sum = REGISTER[x] + REGISTER[y]
            REGISTER[0xF] = sum > 0xFF and 1 or 0
            REGISTER[x] = band(sum, 0xFF)
            if debug then print("8XY4 - V["..x.."] + V["..y.."], VF="..REGISTER[0xF]) end
            
        elseif op == 0x5 then -- 8XY5: VX = VX - VY, set VF on NOT borrow
            REGISTER[0xF] = REGISTER[x] >= REGISTER[y] and 1 or 0
            REGISTER[x] = band(REGISTER[x] - REGISTER[y], 0xFF)
            if debug then print("8XY5 - V["..x.."] - V["..y.."], VF="..REGISTER[0xF]) end
            
        elseif op == 0x6 then -- 8XY6: VX = VX >> 1, set VF to LSB
            REGISTER[0xF] = band(REGISTER[x], 0x1)
            REGISTER[x] = rshift(REGISTER[x], 1)
            if debug then print("8XY6 - V["..x.."] >> 1, VF="..REGISTER[0xF]) end
            
        elseif op == 0x7 then -- 8XY7: VX = VY - VX, set VF on NOT borrow
            REGISTER[0xF] = REGISTER[y] >= REGISTER[x] and 1 or 0
            REGISTER[x] = band(REGISTER[y] - REGISTER[x], 0xFF)
            if debug then print("8XY7 - V["..y.."] - V["..x.."], VF="..REGISTER[0xF]) end
            
        elseif op == 0xE then -- 8XYE: VX = VX << 1, set VF to MSB
            REGISTER[0xF] = rshift(REGISTER[x], 7)
            REGISTER[x] = band(lshift(REGISTER[x], 1), 0xFF)
            if debug then print("8XYE - V["..x.."] << 1, VF="..REGISTER[0xF]) end
        end

    elseif INSTRUCTION_NUMBER == 0x9 then -- 9XY0: Skip if VX != VY
        if band(INSTRUCTION, 0x000F) == 0 then
            if REGISTER[x] ~= REGISTER[y] then
                PC = PC + 2
            end
            if debug then print("9XY0 - SKIP if V["..x.."] != V["..y.."]") end
        end

    elseif INSTRUCTION_NUMBER == 0xA then -- ANNN: Set I = NNN
        I = band(INSTRUCTION, 0x0FFF)
        if debug then print("ANNN - SET I = " .. I) end

    elseif INSTRUCTION_NUMBER == 0xB then -- BNNN: Jump to NNN + V0
        local address = band(INSTRUCTION, 0x0FFF)
        PC = address + REGISTER[0]
        if debug then print("BNNN - JUMP to " .. address .. " + V0") end

    elseif INSTRUCTION_NUMBER == 0xC then -- CXNN: VX = random AND NN
        REGISTER[x] = band(math.random(0, 255), SECOND_BYTE)
        if debug then print("CXNN - V["..x.."] = RAND & "..SECOND_BYTE) end

    elseif INSTRUCTION_NUMBER == 0xD then -- DXYN: Draw sprite
        local n = band(SECOND_BYTE, 0x0F)
        local xPos = REGISTER[x] % 64
        local yPos = REGISTER[y] % 32
        
        REGISTER[0xF] = 0
        
        for row = 0, n-1 do
            local spriteByte = MEMORY[I + row]
            for col = 0, 7 do
                local pixel = band(rshift(spriteByte, 7 - col), 0x1)
                if pixel == 1 then
                    local displayX = (xPos + col) % 64
                    local displayY = (yPos + row) % 32
                    
                    if DISPLAY[displayY][displayX] == 1 then
                        REGISTER[0xF] = 1
                    end
                    
                    DISPLAY[displayY][displayX] = bxor(DISPLAY[displayY][displayX], 1)
                end
            end
        end
        
        if debug then print("DXYN - DRAW at ("..xPos..","..yPos.."), height "..n) end

    elseif INSTRUCTION_NUMBER == 0xE then
        if SECOND_BYTE == 0x9E then -- EX9E: Skip if key pressed
            if lib.isKeyPressed(REGISTER[x]) then
                PC = PC + 2
            end
            if debug then print("EX9E - SKIP if key "..REGISTER[x].." pressed") end
            
        elseif SECOND_BYTE == 0xA1 then -- EXA1: Skip if key not pressed
            if not lib.isKeyPressed(REGISTER[x]) then
                PC = PC + 2
            end
            if debug then print("EXA1 - SKIP if key "..REGISTER[x].." not pressed") end
        end

    elseif INSTRUCTION_NUMBER == 0xF then
        if SECOND_BYTE == 0x07 then -- FX07: VX = delay timer
            REGISTER[x] = DELAY_TIMER
            if debug then print("FX07 - V["..x.."] = DELAY_TIMER ("..DELAY_TIMER..")") end
            
        elseif SECOND_BYTE == 0x15 then -- FX15: delay timer = VX
            DELAY_TIMER = REGISTER[x]
            if debug then print("FX15 - DELAY_TIMER = V["..x.."] ("..REGISTER[x]..")") end
            
        elseif SECOND_BYTE == 0x18 then -- FX18: sound timer = VX
            SOUND_TIMER = REGISTER[x]
            if debug then print("FX18 - SOUND_TIMER = V["..x.."] ("..REGISTER[x]..")") end
            
        elseif SECOND_BYTE == 0x1E then -- FX1E: I += VX
            I = I + REGISTER[x]
            if I > 0xFFF then
                REGISTER[0xF] = 1
            else
                REGISTER[0xF] = 0
            end
            if debug then print("FX1E - I += V["..x.."], I="..I) end
            
        elseif SECOND_BYTE == 0x0A then -- FX0A: Wait for key press
        	local keyPressed = nil
            for keyCode = 0, 15 do
                if lib.isKeyPressed(keyCode) then
                    keyPressed = keyCode
                    break
                end
            end
            
            if keyPressed then
                REGISTER[x] = keyPressed
            else
                PC = PC - 2 -- Try again next cycle
            end
            if debug then print("FX0A - WAIT for key, got "..(keyPressed or "none")) end
            
        elseif SECOND_BYTE == 0x29 then -- FX29: I = sprite address for VX
            I = FONT_INDEX + (REGISTER[x] * 5)
            if debug then print("FX29 - I = sprite for V["..x.."] ("..REGISTER[x]..")") end
            
        elseif SECOND_BYTE == 0x33 then -- FX33: BCD store
            local value = REGISTER[x]
            MEMORY[I] = math.floor(value / 100)
            MEMORY[I + 1] = math.floor((value % 100) / 10)
            MEMORY[I + 2] = value % 10
            if debug then print("FX33 - BCD store "..value) end
            
        elseif SECOND_BYTE == 0x55 then -- FX55: Store registers V0-VX
            for i = 0, x do
                MEMORY[I + i] = REGISTER[i]
            end
            if debug then print("FX55 - STORE V0-V["..x.."] at I="..I) end
            
        elseif SECOND_BYTE == 0x65 then -- FX65: Load registers V0-VX
            for i = 0, x do
                REGISTER[i] = MEMORY[I + i]
            end
            if debug then print("FX65 - LOAD V0-V["..x.."] from I="..I) end
        end
    end
end

return lib
