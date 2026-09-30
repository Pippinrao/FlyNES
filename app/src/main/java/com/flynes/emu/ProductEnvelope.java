package com.flynes.emu;
import java.util.LinkedHashMap;
import java.util.Map;
final class ProductEnvelope {
    static Map<String,Object> reply(Object requestId,long generation,String instance,Map<String,?> body) {
        var result=new LinkedHashMap<String,Object>(body);
        result.put("requestId",requestId); result.put("hostGeneration",generation); result.put("instanceId",instance);
        return result;
    }
    static boolean accepts(long incoming,long current,boolean bootstrap) {
        return current>0 && (incoming==current || (bootstrap && incoming==0));
    }
}
