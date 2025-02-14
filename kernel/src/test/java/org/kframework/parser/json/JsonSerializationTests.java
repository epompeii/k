// Copyright (c) K Team. All Rights Reserved.
package org.kframework.parser.json;

import static org.kframework.Collections.immutable;
import static org.kframework.kore.KORE.*;

import com.google.common.collect.Sets;
import java.io.UnsupportedEncodingException;
import java.nio.charset.StandardCharsets;
import javax.json.Json;
import javax.json.JsonObjectBuilder;
import javax.json.JsonStructure;
import junit.framework.Assert;
import org.junit.Test;
import org.kframework.attributes.Att;
import org.kframework.attributes.Source;
import org.kframework.definition.Definition;
import org.kframework.definition.Module;
import org.kframework.kore.K;
import org.kframework.parser.ParserUtils;
import org.kframework.unparser.ToJson;

public class JsonSerializationTests {

  @Test
  public void test1() {
    K k =
        KApply(
            KLabel("#ruleNoConditions"),
            KApply(
                KLabel("#KRewrite"),
                KApply(
                    KLabel("tuplee"),
                    KApply(KLabel("#SemanticCastToE"), KToken("A", Sort("#KVariable"))),
                    KApply(KLabel("#SemanticCastToE"), KToken("B", Sort("#KVariable"))),
                    KApply(KLabel("#SemanticCastToS"), KToken("C", Sort("#KVariable")))),
                KApply(KLabel("#SemanticCastToS"), KToken("C", Sort("#KVariable")))));

    JsonStructure js = ToJson.toJson(k);
    JsonObjectBuilder term = Json.createObjectBuilder();
    term.add("format", "KAST");
    term.add("version", ToJson.version);
    term.add("term", js);
    K k2 = JsonParser.parseJson(term.build());
    Assert.assertEquals(k, k2);
  }

  @Test
  public void test2() {
    K k =
        KApply(
            KLabel("#ruleNoConditions", Sort("X", Sort("6"), Sort("Z"))),
            KApply(
                KLabel("#KRewrite", Sort("P")),
                KApply(
                    KLabel("tuplee"),
                    KApply(KLabel("#SemanticCastToE"), KToken("A", Sort("#KVariable"))),
                    KApply(KLabel("#SemanticCastToE"), KToken("B", Sort("#KVariable"))),
                    KApply(KLabel("#SemanticCastToS"), KToken("C", Sort("#KVariable")))),
                KApply(KLabel("#SemanticCastToS"), KToken("C", Sort("#KVariable")))));

    JsonStructure js = ToJson.toJson(k);
    JsonObjectBuilder term = Json.createObjectBuilder();
    term.add("format", "KAST");
    term.add("version", ToJson.version);
    term.add("term", js);
    K k2 = JsonParser.parseJson(term.build());
    Assert.assertEquals(k, k2);
  }

  @Test
  public void test3() throws UnsupportedEncodingException {
    String defstr =
        ""
            + "module TEST "
            + "syntax Exp ::= Exp \"+\" Exp [klabel('Plus), prefer] "
            + "| Exp \"*\" Exp [klabel('Mul)] "
            + "| r\"[0-9]+\" [token] "
            + "syntax K "
            + "syntax TopCell ::= \"<T>\" KCell StateCell \"</T>\" [klabel(<T>), cell] "
            + "syntax KCell ::= \"<k>\" K \"</k>\" [klabel(<k>), cell] "
            + "syntax StateCell ::= \"<state>\" K \"</state>\" [klabel(<state>), cell] "
            + "endmodule";

    Module mod =
        ParserUtils.parseMainModuleOuterSyntax(
            defstr, Source.apply("generated by RuleGrammarTest"), "TEST");
    Definition def1 = Definition.apply(mod, immutable(Sets.newHashSet(mod)), Att.empty());

    String inputDefinition = new String(ToJson.apply(def1), StandardCharsets.UTF_8);
    Definition def2 = JsonParser.parseDefinition(inputDefinition);

    Assert.assertEquals(def1, def2);
  }
}
