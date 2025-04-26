local ESX = exports['es_extended']:getSharedObject()
local isRestoring = false
local lastSavedVehicle = nil
local lastVehiclePlate = nil
local lastSaveTime = 0
local wasInVehicle = false
local restoreAttempts = 0

local Config = {
    Debug = true,
    DebugLevel = 2,
    MaxRestoreAttempts = 5,
    RestoreDelay = 3000,
    DisableControlsDuringRestore = true,
    AutoSaveInterval = 10000,
    PositionCheckThreshold = 3.0,
    HeadingCheckThreshold = 15.0
}

local function DebugPrint(msg, level)
    if not Config.Debug then return end
    level = level or 1
    if level > Config.DebugLevel then return end

    local time = os.date("%H:%M:%S")
    local prefixes = { "[INFO]", "[DETAIL]", "[FULL]" }
    print(("%s [%s] %s"):format(prefixes[level] or "[DEBUG]", time, msg))
end

local function FindPedVehicleSeat(ped, vehicle)
    if not DoesEntityExist(ped) or not DoesEntityExist(vehicle) then return -1 end

    for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) do
        if GetPedInVehicleSeat(vehicle, i) == ped then
            DebugPrint(("Siège trouvé: %d"):format(i), 2)
            return i
        end
    end
    return -1
end

local function IsVehicleOwned(plate, cb)
    ESX.TriggerServerCallback('ch_deco_veh:checkVehicleOwner', function(result)
        DebugPrint(("Propriété vérifiée pour %s: %s"):format(plate, tostring(result)), 2)
        cb(result or false)
    end, plate)
end

local function ValidateVehicleData(data)
    if not data then return false end
    if not data.model or type(data.model) ~= 'number' then return false end
    if not data.position or type(data.position.x) ~= 'number' then return false end
    if not data.heading or type(data.heading) ~= 'number' then return false end
    if not data.plate or type(data.plate) ~= 'string' then return false end
    return true
end

local function SaveCurrentVehicle(forceSave)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return false end

    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        if not DoesEntityExist(vehicle) then return false end

        local plate = GetVehicleNumberPlateText(vehicle) or "NOPLATE"
        local model = GetEntityModel(vehicle)
        local modelName = GetDisplayNameFromVehicleModel(model)

        DebugPrint(("Sauvegarde modèle - Hash: %s, Nom: %s"):format(model, modelName), 2)

        IsVehicleOwned(plate, function(owned)
            local data = {
                netId = NetworkGetNetworkIdFromEntity(vehicle),
                model = model,
                modelName = modelName,
                plate = plate,
                seat = FindPedVehicleSeat(ped, vehicle),
                position = GetEntityCoords(vehicle),
                heading = GetEntityHeading(vehicle),
                properties = ESX.Game.GetVehicleProperties(vehicle)
            }

            if ValidateVehicleData(data) then
                lastSavedVehicle = data
                TriggerServerEvent('ch_deco_veh:saveVehicleData', {
                    vehicleData = data,
                    owned = owned
                })
                DebugPrint(("Véhicule sauvegardé - Plaque: %s"):format(data.plate), 1)
                return true
            else
                DebugPrint("Données du véhicule invalides", 1)
                return false
            end
        end)
    elseif forceSave and lastSavedVehicle then
        TriggerServerEvent('ch_deco_veh:clearVehicleData')
        return false
    end
end

RegisterNetEvent('ch_deco_veh:requestVehicleSave', function()
    SaveCurrentVehicle(true)
end)

local function SpawnVehicleWithRetry(vehicleData, cb)
    local attempts = 0
    local spawnedVehicle = nil

    local function TrySpawn()
        attempts = attempts + 1
        
        ESX.Game.SpawnVehicle(vehicleData.model, vehicleData.position, vehicleData.heading, function(vehicle)
            if DoesEntityExist(vehicle) then
                spawnedVehicle = vehicle
                if cb then cb(vehicle) end
            elseif attempts < 3 then
                DebugPrint(("Tentative de spawn échouée (%d/3)"):format(attempts), 1)
                Citizen.Wait(500)
                TrySpawn()
            else
                DebugPrint("Échec définitif du spawn du véhicule", 1)
                if cb then cb(nil) end
            end
        end)
    end

    TrySpawn()
end

RegisterNetEvent('ch_deco_veh:restoreVehicle', function(vehicleData)
    if not vehicleData or isRestoring then return end
    if not ValidateVehicleData(vehicleData) then
        DebugPrint("Données de véhicule invalides pour la restauration", 1)
        return
    end

    DebugPrint("Tentative de restauration du véhicule...", 1)
    isRestoring = true
    restoreAttempts = 0

    local function AttemptRestoration()
        restoreAttempts = restoreAttempts + 1
        
        ESX.TriggerServerCallback('ch_deco_veh:getVehicleNetId', function(netId)
            local vehicle = nil
            
            if netId then
                vehicle = NetToVeh(netId)
                if DoesEntityExist(vehicle) then
                    DebugPrint("Véhicule réseau trouvé - warp direct", 2)
                    RestoreIntoVehicle(vehicle, vehicleData.seat, vehicleData.properties)
                    return
                end
            end

            local vehicles = GetGamePool('CVehicle')
            for _, v in ipairs(vehicles) do
                if DoesEntityExist(v) and GetVehicleNumberPlateText(v) == vehicleData.plate then
                    vehicle = v
                    DebugPrint("Véhicule existant trouvé localement avec la même plaque", 2)
                    break
                end
            end

            if vehicle and DoesEntityExist(vehicle) then
                RestoreIntoVehicle(vehicle, vehicleData.seat, vehicleData.properties)
            else
                DebugPrint("Pas de véhicule existant, création d'un nouveau", 2)
                SpawnVehicleWithRetry(vehicleData, function(spawnedVehicle)
                    if spawnedVehicle then
                        RestoreIntoVehicle(spawnedVehicle, vehicleData.seat, vehicleData.properties)
                    else
                        isRestoring = false
                        ESX.ShowNotification('~r~Erreur de restauration du véhicule')
                    end
                end)
            end
        end, vehicleData.plate)
    end

    AttemptRestoration()

    Citizen.CreateThread(function()
        while isRestoring and restoreAttempts < Config.MaxRestoreAttempts do
            Citizen.Wait(Config.RestoreDelay)
            if isRestoring then
                DebugPrint(("Nouvelle tentative de restauration (%d/%d)"):format(restoreAttempts, Config.MaxRestoreAttempts), 1)
                AttemptRestoration()
            end
        end
    end)
end)

function RestoreIntoVehicle(vehicle, seat, properties)
    if not DoesEntityExist(vehicle) then
        isRestoring = false
        return
    end

    local ped = PlayerPedId()
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)

    if Config.DisableControlsDuringRestore then
        DisableAllControlActions(0)
    end

    if properties then
        ESX.Game.SetVehicleProperties(vehicle, properties)
        DebugPrint("Propriétés du véhicule appliquées", 2)
    end

    TaskWarpPedIntoVehicle(ped, vehicle, seat or -1)
    
    Citizen.Wait(500)
    if IsPedInVehicle(ped, vehicle, false) then
        ESX.ShowNotification('~g~Véhicule restauré avec succès')
        DebugPrint("Restauration réussie", 1)
        isRestoring = false
        lastSavedVehicle = nil
    else
        DebugPrint("Échec de réintégration dans le véhicule", 1)
    end

    if Config.DisableControlsDuringRestore then
        EnableAllControlActions(0)
    end
end

Citizen.CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local inVehicle = IsPedInAnyVehicle(ped, false)

        if inVehicle then
            wasInVehicle = true
            local vehicle = GetVehiclePedIsIn(ped, false)
            local plate = GetVehicleNumberPlateText(vehicle)
            local currentTime = GetGameTimer()

            if plate ~= lastVehiclePlate or (currentTime - lastSaveTime) >= Config.AutoSaveInterval then
                if SaveCurrentVehicle() then
                    lastVehiclePlate = plate
                    lastSaveTime = currentTime
                end
            end
        elseif wasInVehicle then
            wasInVehicle = false
            lastVehiclePlate = nil
            Citizen.Wait(30000)
            if not IsPedInAnyVehicle(PlayerPedId(), false) then
                TriggerServerEvent('ch_deco_veh:clearVehicleData')
            end
        end

        Citizen.Wait(1000)
    end
end)

Citizen.CreateThread(function()
    while not ESX do
        Citizen.Wait(100)
        ESX = exports['es_extended']:getSharedObject()
    end
    DebugPrint("Client initialisé", 1)
end)

RegisterCommand('vehdebug', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        local model = GetEntityModel(vehicle)
        DebugPrint(("Véhicule actuel - Hash: %s, Plaque: %s"):format(model, GetVehicleNumberPlateText(vehicle)), 1)
    else
        DebugPrint("Pas dans un véhicule", 1)
        if lastSavedVehicle then
            DebugPrint(("Dernier véhicule sauvegardé - Plaque: %s"):format(lastSavedVehicle.plate), 1)
        end
    end
end, false)