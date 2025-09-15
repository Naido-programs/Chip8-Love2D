io.stdout:setvbuf('no')
chip8 = require "Chip8Lib"

function love.load()
	fileName = "4-flags.ch8"
	chip8.loadROM(fileName)
    
    -- Configuración de velocidad
    paused = false
    baseSpeed = 10  -- Instrucciones por frame
    currentSpeed = baseSpeed
    targetFPS = 60
    actualFPS = 0
    
    scale = 10
    local w = 64 * scale
    local h = 32 * scale
    love.window.setMode(w, h)
    
    -- Controles de velocidad
    speedMultipliers = {0.25, 0.5, 1, 2, 4, 8}
    currentMultiplier = 3  -- Empieza en velocidad normal (1x)
    
    love.timer.sleep(0.1)  -- Pequeña pausa inicial
end

function love.update(dt)
	if dt > 0 then
	    actualFPS = 1 / dt
	else
	    actualFPS = 0
	end
    
    if not paused then
        -- Calcular instrucciones a ejecutar basado en velocidad
        local instructionsToExecute = math.floor(currentSpeed * speedMultipliers[currentMultiplier])
        
        for i = 1, instructionsToExecute do
            chip8.fetch()
            chip8.decode(false)
        end
        
        -- Actualizar timers una vez por frame (60Hz)
        chip8.updateTimers()
    end
end

function love.draw()
	local display = chip8.getDisplay()
    love.graphics.setColor(0.2,0.2,0.2,1)
    love.graphics.rectangle("fill",0,0,scale*64,scale*32)
    love.graphics.setColor(0,0.8,0,1)
    
    for x = 0, 63 do
        for y = 0, 31 do
            if display[y] and display[y][x] == 1 then
                love.graphics.rectangle("fill", x*scale, y*scale, scale, scale)
            end
        end
    end
    
    -- Mostrar información de velocidad y FPS
    love.graphics.setColor(1,1,1,1)
    love.graphics.print("FPS: " .. math.floor(actualFPS), 5, 5)
    love.graphics.print("Speed: " .. speedMultipliers[currentMultiplier] .. "x", 5, 25)
    love.graphics.print("Inst/frame: " .. math.floor(currentSpeed * speedMultipliers[currentMultiplier]), 5, 45)
    love.graphics.print("Paused: " .. tostring(paused), 5, 65)
end

function love.keyreleased(key)
	chip8.setKeypad(key, false)
end

function love.keypressed(key)
   if key == "escape" then
        love.event.quit()
    elseif key == "space" then
        paused = not paused
    elseif key == "up" then
        -- Aumentar velocidad
        currentMultiplier = math.min(currentMultiplier + 1, #speedMultipliers)
    elseif key == "down" then
        -- Reducir velocidad
        currentMultiplier = math.max(currentMultiplier - 1, 1)
    elseif key == "m" then
        -- Reset
        chip8.loadROM(fileName)
    endaused = not paused
   end
   chip8.setKeypad(key, true)
end

function love.focus(focused)
    if not focused then
        -- Liberar todas las teclas cuando la ventana pierde foco
        for i, v in ipairs({"x","1","2","3","q","w","e","a","s","d","z","c","4","r","f","v"}) do
            chip8.setKeypad(v, false)
        end
    end
end
