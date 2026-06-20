import 'package:flutter_test/flutter_test.dart';
import 'package:occasion/services/id_document_parser.dart';

void main() {
  test("detecte une carte d'electeur et ses champs utiles", () {
    final result = IdDocumentParser.parse('''
CARTE D'ELECTEUR
Numero electeur : EL-45891230
Nom et prenoms : KOUAME JEAN
Date de naissance : 12/04/1986
Centre de vote : ECOLE CENTRALE
Bureau de vote : BV 04
Commune : ABIDJAN
''');

    expect(result, contains("Document : Carte d'electeur"));
    expect(result, contains('Numero : EL-45891230'));
    expect(result, contains('Nom : KOUAME JEAN'));
    expect(result, contains('DateNaissance : 12/04/1986'));
    expect(result, contains('CentreVote : ECOLE CENTRALE'));
    expect(result, contains('BureauVote : BV 04'));
    expect(result, contains('Commune : ABIDJAN'));
  });

  test('conserve la detection CNI existante', () {
    final result = IdDocumentParser.parse('''
CARTE NATIONALE D'IDENTITE
CNI : 123456789
Nom : DIARRA AMINATA
Nee le 01/01/1990
''');

    expect(result, contains('Document : Carte nationale'));
    expect(result, contains('Numero : 123456789'));
    expect(result, contains('Nom : DIARRA AMINATA'));
    expect(result, contains('DateNaissance : 01/01/1990'));
  });
}
