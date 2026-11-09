# Quem pode mexer no repositório

O repositório é [bakermarcos/volta](https://github.com/bakermarcos/volta). A branch padrão é `master`.

## Master

Qualquer pessoa pode abrir um pull request. Merge na `master` só a conta **bakermarcos** consegue fazer.

O pull request precisa da revisão de `@bakermarcos`, dono de tudo em `.github/CODEOWNERS`. Enquanto essa revisão não existir, o merge fica bloqueado. Outra conta, mesmo com permissão de escrita, não conclui o merge: a regra **Master: só o dono faz merge** só deixa o dono atualizar a `master`, e apenas pelo pull request. Push direto e force push na `master` são recusados.

Aceitar é aprovar o pull request e, em seguida, fazer o merge. As duas ações são da mesma conta.

## Branches criadas pelo dono

Toda branch fora de `contrib/` só pode ser criada, atualizada ou apagada por pessoas autorizadas. Hoje a pessoa autorizada é **bakermarcos**. Force push nessas branches também fica restrito a essa lista.

Para autorizar outra pessoa numa branch dessas, sem dar a ela o merge da `master`:

1. Abra as regras do repositório em Settings → Rules → Rulesets.
2. Na regra **Branches do dono: só pessoas autorizadas**, adicione a conta em Bypass.
3. Deixe o modo **Always**. Não adicione essa conta na regra da `master`.

## Branches de outras pessoas

Quem for colaborador abre a branch com o prefixo `contrib/`, por exemplo `contrib/ajuste-hud`. Essa prefixo está fora da trava das branches do dono, então o autor empurra os commits dela. O pull request continua sujeito à regra da `master`: só entra depois do aceite, e só o dono faz o merge.

Quem não é colaborador faz o pull request a partir de um fork. Não precisa de branch `contrib/`.

## Segurança do repositório

O código é público. A sala de jogo não é: ela só existe na rede da casa, e o endereço da TV não entra no repositório.

A varredura de segredo, o bloqueio de push com segredo, o alerta de dependência vulnerável e o relato privado já estão ligados no GitHub.

O arquivo `.github/dependabot.yml` pede a atualização semanal do Dart e do Flutter. Ele passa a valer quando estiver na `master`.

Relato de falha fica em privado, pelo caminho descrito em [SECURITY.md](../SECURITY.md). Não abra issue pública com IP, código da sala ou certificado.
