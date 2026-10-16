import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("ScratchProbe9")
struct ScratchProbe9Tests {
    @Test func dist() {
        let good = [("Pytest","pie test"),("Kubelet","cube lit"),("Priya","pry a"),("Uttrflow","utter flow"),("Figma","fig ma"),("Ollama","oh llama"),("Vercel","ver sell"),("Supabase","super base"),("Nginx","engine x"),("Tailwind","tail wind"),("PaymentSheet","payment sheet"),("Kubectl","cube cuttle"),("Databricks","data bricks"),("Snowflake","snow flake"),("Prometheus","prom ethius"),("Ishaan","ee shaan"),("Deepak Rao","deep ack rao"),("Claude","clawed"),("Redis","readees"),("Grafana","grafna"),("Postgres","post gress"),("Kubernetes","cube er net ease"),("Sonnet","son it")]
        let bad = [("iOS","is a"),("Ada","it to"),("Istio","is it"),("Okta","a good"),("Istio","I said"),("Dask","disk I/O"),("eBay","o bhai"),("Dart","try to"),("Dart","to red"),("Julia","shall we"),("Cobra","keep your"),("Bun","buy new"),("Spark","spare key"),("Hive","have a"),("Mira","me where"),("Zoe","so I"),("Ruby","rupaye aaya"),("Go","kya you"),("Arc","hour ago"),("Okta","was a good"),("Istio","is at"),("Istio","used to"),("Okta","I go to"),("Istio","US at")]
        for (a,b) in good { print("D9 good \(a) / \(b) d=\(String(describing: PhonemeLexicon.shared.soundDistance(a, b)))") }
        for (a,b) in bad { print("D9 bad \(a) / \(b) d=\(String(describing: PhonemeLexicon.shared.soundDistance(a, b)))") }
    }
}
