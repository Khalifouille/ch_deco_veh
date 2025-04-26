local ESX = exports['es_extended']:getSharedObject()
local savedVehicles = {}

local Config = {
    MaxReconnectTime = 3600,
    EnableDatabase = true,
    Notifications = true,
    Debug = true,
    SaveCooldown = 3000,
    DatabaseTable = 'vehicle_reconnect'
}

function DebugPrint(msg)
    if Config.Debug then
        print(('[VEHICLE-RECONNECT][SERVER] %s'):format(msg))
    end
end

MySQL.ready(function()
    if Config.EnableDatabase then
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS `vehicle_reconnect` (
                `identifier` VARCHAR(60) NOT NULL,
                `vehicle_data` LONGTEXT,
                `timestamp` INT(11),
                PRIMARY KEY (`identifier`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]], {}, function(success)
            DebugPrint("Table DB prête")
        end)
    end
end)

local function SaveToDatabase(identifier, data)
    if not Config.EnableDatabase then return end
    MySQL.Async.execute([[
        INSERT INTO `vehicle_reconnect` (identifier, vehicle_data, timestamp)
        VALUES (@identifier, @data, @timestamp)
        ON DUPLICATE KEY UPDATE vehicle_data = @data, timestamp = @timestamp
    ]], {
        ['@identifier'] = identifier,
        ['@data'] = json.encode(data),
        ['@timestamp'] = os.time()
    }, function(rowsChanged)
        DebugPrint(("Sauvegarde DB: %d ligne(s)"):format(rowsChanged or 0))
    end)
end

local function LoadFromDatabase(identifier, cb)
    if not Config.EnableDatabase then return cb(nil) end
    MySQL.Async.fetchScalar('SELECT vehicle_data FROM vehicle_reconnect WHERE identifier = @identifier', {
        ['@identifier'] = identifier
    }, function(result)
        cb(result and json.decode(result))
    end)
end

RegisterNetEvent('ch_deco_veh:clearVehicleData', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    savedVehicles[src] = nil
    MySQL.Async.execute('DELETE FROM vehicle_reconnect WHERE identifier = @identifier', {
        ['@identifier'] = xPlayer.identifier
    })
end)

ESX.RegisterServerCallback('ch_deco_veh:checkVehicleOwner', function(source, cb, plate)
    cb(true)
end)

ESX.RegisterServerCallback('ch_deco_veh:getVehicleNetId', function(source, cb, plate)
    for _, vData in pairs(savedVehicles) do
        if vData.plate == plate then
            cb(vData.netId)
            return
        end
    end
    cb(nil)
end)

RegisterNetEvent('ch_deco_veh:saveVehicleData', function(data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not data or not data.vehicleData then
        return
    end

    local vehicleData = data.vehicleData
    savedVehicles[src] = vehicleData

    SaveToDatabase(xPlayer.identifier, vehicleData)

    DebugPrint("Véhicule sauvegardé pour "..vehicleData.plate)
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    Citizen.SetTimeout(Config.SaveCooldown, function()
        if not savedVehicles[src] then
            TriggerClientEvent('ch_deco_veh:requestVehicleSave', src)
        end
    end)
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    Citizen.SetTimeout(5000, function()
        if savedVehicles[playerId] then
            TriggerClientEvent('ch_deco_veh:restoreVehicle', playerId, savedVehicles[playerId])
            return
        end

        LoadFromDatabase(xPlayer.identifier, function(vehicleData)
            if vehicleData then
                local timeDiff = os.time() - vehicleData.timestamp
                if timeDiff <= Config.MaxReconnectTime then
                    savedVehicles[playerId] = vehicleData
                    TriggerClientEvent('ch_deco_veh:restoreVehicle', playerId, vehicleData)
                end
            end
        end)
    end)
end)

Citizen.CreateThread(function()
    while not ESX do
        Citizen.Wait(100)
        ESX = exports['es_extended']:getSharedObject()
    end
    DebugPrint("Serveur initialisé")
end)
