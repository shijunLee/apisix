--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local local_conf         = require("apisix.core.config_local").local_conf()
local core               = require("apisix.core")
local ipmatcher          = require("resty.ipmatcher")
local ipairs             = ipairs
local ngx                = ngx
local ngx_timer_at       = ngx.timer.at
local ngx_timer_every    = ngx.timer.every
local log                = core.log
local etcd              = require("resty.etcd")
local default_weight
local applications


local _M = {
    version = 0.1,
}

-- go micro etcd prefix /micro/registry/
local function service_info()
    local etcd_conf
    if local_conf.discovery and local_conf.discovery.etcd then 
        etcd_conf = local_conf.discovery.etcd
    else 
        return 
    end 
    if not etcd_conf.http_host then
        log.error("do not set etcd.http_host")
        return 
    end
    if not etcd_conf.protocol then
        etcd_conf.protocol = "v3"
    end
    if not etcd_conf.prefix then
        etcd_conf.prefix = "/micro/registry"
    end
    etcd_conf.ssl_verify = true
    if etcd_conf.tls then
        if etcd_conf.tls.verify == false then
            etcd_conf.ssl_verify = false
        end

        if etcd_conf.tls.cert then
            etcd_conf.ssl_cert_path = etcd_conf.tls.cert
            etcd_conf.ssl_key_path = etcd_conf.tls.key
        end

        if etcd_conf.tls.sni then
            etcd_conf.sni = etcd_conf.tls.sni
        end
    end  
    return etcd_conf
end

local function parse_instance(app_name,instance)

    local address = instance.address
    local address_array = {}
    string.gsub(address,"([^:]+)",
    function(c)
            table.insert(address_array,c)
        end
    )
    if #address_array ~= 2 then
        return
    end 
    local  ip = address_array[1]
    local port_str = address_array[2]
 
    if not ipmatcher.parse_ipv4(ip) and
            not ipmatcher.parse_ipv6(ip) then 
                log.error(app_name, " service ", instance.address, " node IP ", ip,
                " is invalid(must be IPv4 or IPv6).")
        return
    end 
    local port = tonumber(port_str,10)
    return ip, port, instance.metadata
end



local function fetch_full_registry(premature)
    if premature then
        return
    end

    local etcd_conf = service_info()
    if not etcd_conf then
        return
    end
    local etcd_cli, err = etcd.new(etcd_conf)
    if err then
        log.error("get etcd cli client error")
        return
    end
    
    local data, err =  etcd_cli:readdir(etcd_conf.prefix)
    if not data then
        log.error("read etcd dir error: ", err)
        return
    end
 
    
    local apps = data.body.kvs
    local up_apps = core.table.new(0, #apps)
    for _, app in ipairs(apps) do
        for _, instance in ipairs(app.value.nodes) do
            local ip, port, metadata = parse_instance(app.value.name,instance)
            if ip and port then
                local nodes = up_apps[app.value.name]
                if not nodes then
                    nodes = core.table.new(#app.value.nodes, 0)
                    up_apps[app.value.name] = nodes
                end
                core.table.insert(nodes, {
                    host = ip,
                    port = port,
                    weight = metadata and metadata.weight or default_weight,
                    metadata = metadata,
                })
                if metadata then
                    -- remove useless data
                    metadata.weight = nil
                end
            end
        end
    end
    applications = up_apps
end


function _M.nodes(service_name)
    if not applications then
        log.error("failed to fetch nodes for : ", service_name)
        return
    end

    return applications[service_name]
end


function _M.init_worker()
    default_weight = local_conf.discovery.etcd.weight or 100
    log.info("default_weight:", default_weight, ".")
    local fetch_interval = local_conf.discovery.etcd.fetch_interval or 30
    log.info("fetch_interval:", fetch_interval, ".")
    ngx_timer_at(0, fetch_full_registry)
    ngx_timer_every(fetch_interval, fetch_full_registry)
end


function _M.dump_data()
    return {config = local_conf.discovery.etcd, services = applications or {}}
end


return _M
