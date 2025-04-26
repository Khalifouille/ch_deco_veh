local ESX = exports['es_extended']:getSharedObject()
local savedVehicles = {}

local Config = {
    MaxReconnectTime = 3600,
    EnableDatabase = true,
    Notifications = true,
    Debug = true,
    RecreateIfDestroyed = true,
    OnlyOwnedVehicles = false,
    JobVehiclesAllowed = true,
    LocalTesting = true,
    SaveCooldown = 3000,
    DatabaseTable = 'vehicle_reconnect'
}

local CREATE_TABLE_QUERY = [[
    CREATE TABLE IF NOT EXISTS `vehicle_reconnect` (
        `identifier` VARCHAR(60) NOT NULL,
        `vehicle_data` LONGTEXT,
        `timestamp` INT(11),
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local INSERT_VEHICLE_QUERY = [[
    INSERT INTO `vehicle_reconnect` (identifier, vehicle_data, timestamp)
    VALUES (@identifier, @data, @timestamp)
    ON DUPLICATE KEY UPDATE vehicle_data = @data, timestamp = @timestamp
]]

local FETCH_VEHICLE_QUERY = 'SELECT vehicle_data FROM vehicle_reconnect WHERE identifier = @identifier'
local CLEAR_VEHICLE_QUERY = 'DELETE FROM vehicle_reconnect WHERE identifier = @identifier'

function DebugPrint(msg)
    if Config.Debug then
        print(('[VEHICLE-RECONNECT][SERVER] %s'):format(msg))
    end
end

MySQL.ready(function()
    if Config.EnableDatabase then
        MySQL.Async.execute(CREATE_TABLE_QUERY, {}, function(success)
            if success then
                DebugPrint("Table DB prête")
            else
                DebugPrint("Erreur création table")
            end
        end)
    end
end)

local function SaveToDatabase(identifier, data)
    if not Config.EnableDatabase then return end
    MySQL.Async.execute(INSERT_VEHICLE_QUERY, {
        ['@identifier'] = identifier,
        ['@data'] = json.encode(data),
        ['@timestamp'] = os.time()
    }, function(rowsChanged)
        DebugPrint(("Sauvegarde DB: %d ligne(s) modifiée(s)"):format(rowsChanged or 0))
    end)
end

local function LoadFromDatabase(identifier, cb)
    if not Config.EnableDatabase then return cb(nil) end
    MySQL.Async.fetchScalar(FETCH_VEHICLE_QUERY, {
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

    if Config.EnableDatabase then
        MySQL.Async.execute(CLEAR_VEHICLE_QUERY, {
            ['@identifier'] = xPlayer.identifier
        }, function(rowsChanged)
            DebugPrint(("Données effacées pour %s (%d lignes)"):format(xPlayer.getName(), rowsChanged or 0))
        end)
    end
end)

ESX.RegisterServerCallback('ch_deco_veh:checkVehicleOwner', function(source, cb, plate)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(false) end

    if Config.OnlyOwnedVehicles then
        MySQL.Async.fetchScalar('SELECT 1 FROM owned_vehicles WHERE plate = @plate AND owner = @owner', {
            ['@plate'] = plate,
            ['@owner'] = xPlayer.identifier
        }, function(result)
            cb(result == 1)
        end)
    else
        cb(true)
    end
end)

ESX.RegisterServerCallback('ch_deco_veh:getVehicleNetId', function(source, cb, plate)
    if not plate then return cb(nil) end
    local netId = VehicleManager and VehicleManager:GetVehicleNetId(plate)
    cb(netId)
end)

RegisterNetEvent('ch_deco_veh:saveVehicleData', function(data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer or not data or not data.vehicleData then
        DebugPrint("Erreur: Données invalides")
        return
    end

    if type(data.vehicleData.model) ~= 'number' then
        DebugPrint("Erreur: Modèle de véhicule invalide (doit être un nombre)")
        return
    end

    local required = {'plate', 'model', 'position'}
    for _, field in ipairs(required) do
        if not data.vehicleData[field] then
            DebugPrint(("Champ manquant: %s"):format(field))
            return
        end
    end

    if not data.owned and Config.OnlyOwnedVehicles then
        DebugPrint(("Véhicule non possédé (%s)"):format(data.vehicleData.plate))
        return
    end

    local vehicleData = {
        netId = data.vehicleData.netId,
        model = data.vehicleData.model,
        modelName = data.vehicleData.modelName or "Inconnu",
        plate = data.vehicleData.plate,
        seat = data.vehicleData.seat or -1,
        position = data.vehicleData.position,
        heading = data.vehicleData.heading or 0.0,
        properties = data.vehicleData.properties or {},
        timestamp = os.time(),
        identifier = xPlayer.identifier,
        job = xPlayer.job.name
    }

    DebugPrint(("Sauvegarde véhicule - Modèle: %s (%s)"):format(vehicleData.modelName, vehicleData.model), 1)

    savedVehicles[src] = vehicleData
    SaveToDatabase(xPlayer.identifier, vehicleData)

    if VehicleManager then
        VehicleManager:Register(vehicleData.netId, vehicleData.plate)
    end
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
            DebugPrint(("Restauration mémoire - Modèle: %s"):format(savedVehicles[playerId].model), 1)
            RestorePlayerToVehicle(playerId, savedVehicles[playerId])
            return
        end

        LoadFromDatabase(xPlayer.identifier, function(vehicleData)
            if vehicleData then
                local timeDiff = os.time() - vehicleData.timestamp
                if timeDiff <= Config.MaxReconnectTime then
                    DebugPrint(("Restauration BDD - Modèle: %s"):format(vehicleData.model), 1)
                    savedVehicles[playerId] = vehicleData
                    RestorePlayerToVehicle(playerId, vehicleData)
                else
                    DebugPrint(("Données expirées (%ds)"):format(timeDiff))
                end
            end
        end)
    end)
end)

function RestorePlayerToVehicle(playerId, vehicleData)
    if not playerId or not vehicleData then return end

    local xPlayer = ESX.GetPlayerFromId(playerId)
    if not xPlayer then return end

    if not Config.JobVehiclesAllowed and vehicleData.job and xPlayer.job.name ~= vehicleData.job then
        DebugPrint(("Métier incorrect (%s)"):format(vehicleData.job))
        return
    end

    local timeDiff = os.time() - vehicleData.timestamp
    if timeDiff > Config.MaxReconnectTime then
        DebugPrint(("Délai expiré (%ds)"):format(timeDiff))
        return
    end

    DebugPrint(("Téléportation véhicule - Plaque: %s"):format(vehicleData.plate), 1)
    TriggerClientEvent('ch_deco_veh:restoreVehicle', playerId, vehicleData)
end

Citizen.CreateThread(function()
    while not ESX do
        Citizen.Wait(100)
        ESX = exports['es_extended']:getSharedObject()
    end
    DebugPrint("Serveur initialisé")
end)
