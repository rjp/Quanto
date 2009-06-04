--local tokenizer    = require("proxy.tokenizer") -- seems broken in 0.7.0

-- share it across all sessions
if not proxy.global.profile_stats then
   proxy.global.profile_stats = {}
end

-- perhaps
-- on something like "dump stats" we inject a real table
-- that way you could use the awesome power of sql for avg, sum, etc.

-- add stats for
--
-- first seen
-- bytes
--  total
--  max
--  avg

-- on query in...
-- respond to a couple of commands
-- or tag it so it hits read_query_result and let it past
function read_query( packet )
   if packet:byte() == proxy.COM_QUERY then
      
      -- check for commands
      local f_s, f_e, command = string.find(packet, "^%s*(%w+)", 2)
      local option

      if f_e then
         -- if that matches, take the next sub-string as option
         f_s, f_e, option = string.find(packet, "^%s+(%w+)", f_e + 1)
      end

      if command and string.lower(command) == "show" and string.lower(option) == "stats" then
         -- turn our fancy structure into something the client can read
         -- proxy.response.resultset.rows[1] should be a table, but is a number

         local results = {}
         local index = 0
         for k,v in pairs(proxy.global.profile_stats) do
            index = index + 1
            results[index] = {k,
                              v.count,
                              string.format("%g",v.time / 1000),
                              string.format("%g",(v.time / v.count) / 1000),
                              string.format("%g",(v.max_time / 1000)),
                              v.row_count,
                              v.row_max,
                              string.format("%g",v.row_count / v.count),
                              v.norm_query
                           }
         end
         
         proxy.response.type = proxy.MYSQLD_PACKET_OK
         proxy.response.resultset = {
            fields = { 
               { type = proxy.MYSQL_TYPE_STRING, name = "module : line : called", },
               { type = proxy.MYSQL_TYPE_LONG,   name = "times called", },
               { type = proxy.MYSQL_TYPE_STRING, name = "total time (ms)", },
               { type = proxy.MYSQL_TYPE_STRING, name = "avg time (ms)", },
               { type = proxy.MYSQL_TYPE_STRING, name = "max time (ms)", },
               { type = proxy.MYSQL_TYPE_LONG,   name = "row count", },
               { type = proxy.MYSQL_TYPE_LONG,   name = "row max", },
               { type = proxy.MYSQL_TYPE_STRING, name = "row avg", },
               { type = proxy.MYSQL_TYPE_STRING, name = "query", },
            }, 
            rows = results                                
         }
         
         -- we have our result, send it back
         return proxy.PROXY_SEND_RESULT
      elseif command and string.lower(command) == "clear" and string.lower(option) == "stats" then
         proxy.global.profile_stats = {}

         -- it would be good if this cleared the query cache at this point as well
         -- or maybe we re-write every query to turn the cache off around it?
         
         proxy.response.type = proxy.MYSQLD_PACKET_OK
         proxy.response.resultset = {            
            fields = { 
               { type = proxy.MYSQL_TYPE_LONG, name = "status" },
            }, 
            rows = { 
               { 'cleared' }
            }
         }
                  
         return proxy.PROXY_SEND_RESULT
      end
      
      -- if you don't do this, then read_query_result isn't triggered
      proxy.queries:append(1, packet, { resultset_is_needed = true} )
      
      return proxy.PROXY_SEND_QUERY
   end
end

---
-- read_query_result() is called when we receive a query result 
-- from the server
--
-- inj.query_time is the query-time in micro-seconds
-- 
-- @return 
--   * nothing or proxy.PROXY_SEND_RESULT to pass the result-set to the client
--

-- also count warns? no_index_used etc?
function read_query_result(inj)
    local packet = assert(inj.query)

    if packet:byte() == proxy.COM_QUERY then
       -- attempt to skip if it's not a s51 query
       if (string.find(packet:sub(2),"[*]/")) then 
          local call_fingerprint = packet:sub(string.find(packet:sub(2),"/[*]")+4,
                                              string.find(packet:sub(2),"[*]/")
                                           )
          local i_row_count = 0
          local i_row_max = 0          
          -- rows is a function, not an array
          if inj.resultset.rows then
             for row in inj.resultset.rows do
                i_row_count = i_row_count + 1
                i_row_max   = i_row_max + 1     
             end
          end
          
          if (proxy.global.profile_stats[call_fingerprint]) then
             local max_time = proxy.global.profile_stats[call_fingerprint].max_time
             if inj.query_time > max_time then
                max_time = inj.query_time
             end

             local row_max = proxy.global.profile_stats[call_fingerprint].row_max
             if i_row_max > row_max then
                row_max = i_row_max
             end
             
             proxy.global.profile_stats[call_fingerprint] = {count = proxy.global.profile_stats[call_fingerprint].count+1,
                                                             time  = proxy.global.profile_stats[call_fingerprint].time+inj.query_time,
                                                             max_time = max_time,
                                                             row_count =  proxy.global.profile_stats[call_fingerprint].row_count + i_row_count,
                                                             row_max   = proxy.global.profile_stats[call_fingerprint].row_max,
                                                             norm_query = proxy.global.profile_stats[call_fingerprint].norm_query
                                                          }
          else
             -- local tokens = tokenizer.tokenize(inj.query)
             -- local norm_query = tokenizer.normalize(tokens)
             
             proxy.global.profile_stats[call_fingerprint] = {count      = 1,
                                                             time       = inj.query_time,
                                                             max_time   = inj.query_time,
                                                             row_count  = i_row_count,
                                                             row_max    = i_row_max,
                                                             norm_query = string.sub(inj.query,string.find(inj.query,"*/")+3,-1),
                                                            }
          end
       end
    end
end
