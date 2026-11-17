using System;
using System.IO;
using System.Reflection;
using System.Text.Json;
namespace FourGSwitch {
static class ProtocolFixtures {
    public static void Run() {
        using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("protocol-cases.json"))
        using(var json=JsonDocument.Parse(stream))foreach(var item in json.RootElement.EnumerateArray()) {
            bool accepted=true;int actual=-1;
            try {actual=Modem.Value(item.GetProperty("response").GetString(),item.GetProperty("key").GetString());}catch(InvalidOperationException){accepted=false;}
            var expected=item.GetProperty("expected");
            if(expected.ValueKind==JsonValueKind.Null ? accepted : !accepted || actual!=expected.GetInt32())throw new Exception("Protocol fixture failed: "+item.GetProperty("name").GetString());
        }
    }
}
}
