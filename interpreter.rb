# Rubyのinterpreterを実装
# 読み込んだプログラムを抽象構文木に変換するのはminrubyのgemに任せる
# 目標はこのプログラムでこのプログラム自身を実行できること
# 基本的には各部分木で再帰をかけることで葉に到達，その値を使って処理していく流れ
require "minruby"

# treeは抽象構文木(配列)，genvは関数定義用のハッシュ，lenvは変数定義用のハッシュ
def evaluate(tree, genv, lenv)
  # 木の場合はtree[0]は節(何らかの処理を示すワード)，葉の場合はtree[0]は"lit"(literal)
  case tree[0]
  # "lit"なので葉の値をそのまま返す
  # minruby_parse("1") => ["lit", 1]
  when "lit"
    tree[1]
  # 節が"+"なら左右それぞれの部分木を足し合わせる
　# minruby_parse("1 + 2") => ["+", ["lit", 1], ["lit", 2]]
  when "+"
    evaluate(tree[1], genv, lenv) + evaluate(tree[2], genv, lenv)
  # minruby_parse("1 - 2") => ["-", ["lit", 1], ["lit", 2]]
  when "-"
    evaluate(tree[1], genv, lenv) - evaluate(tree[2], genv, lenv)
  # minruby_parse("1 * 2") => ["*", ["lit", 1], ["lit", 2]]
  # 以下，処理は変わらないので省略
  when "*"
    evaluate(tree[1], genv, lenv) * evaluate(tree[2], genv, lenv)
  when "/"
    evaluate(tree[1], genv, lenv) / evaluate(tree[2], genv, lenv)
  when "%"
    evaluate(tree[1], genv, lenv) % evaluate(tree[2], genv, lenv)
  when "**"
    evaluate(tree[1], genv, lenv) ** evaluate(tree[2], genv, lenv)
  when "<"
    evaluate(tree[1], genv, lenv) < evaluate(tree[2], genv, lenv)
  when "<="
    evaluate(tree[1], genv, lenv) <= evaluate(tree[2], genv, lenv)
  when "=="
    evaluate(tree[1], genv, lenv) == evaluate(tree[2], genv, lenv)
  when ">="
    evaluate(tree[1], genv, lenv) >= evaluate(tree[2], genv, lenv)
  when ">"
    evaluate(tree[1], genv, env) > evaluate(tree[2], genv, lenv)
  # stmts(statements)，つまり複文
  # プログラムは全体として複文になっている
  # minruby_parse("1 + 2; 3 * 4")
  # => ["stmts", ["+", ["lit", 1], ["lit", 2]], ["*", ["lit", 3], ["lit", 4]]]
  # 部分木を左から順番に計算すれば良さそう，つまりtree[1]以降を順に計算
  when "stmts"
    i = 1
    last = nil
    while tree[i]
      last = evaluate(tree[i], genv, lenv)
      i = i + 1
    end
    # Rubyでは一番最後に実行された結果をそのまま返す
    last
  # 変数代入
  # minruby_parse("x = 1") => ["var_assign", "x", ["lit", 1]]
  # 右側の部分木を計算した結果を左側の変数に代入
  # つまり変数名と代入すべき値を対応付けて覚えさせる
  # ハッシュのkeyとして変数名，そこに対応する値をvalueとして書き込む
  when "var_assign"
    lenv[tree[1]] = evaluate(tree[2], genv, lenv)
  # 変数参照
  # minruby_parse("x = 1; x")
  # => ["stmts", ["var_assign", "x", ["lit", 1]], ["var_ref", "x"]]
  # ハッシュの中で変数名に対応する値を読み出すだけ
  when "var_ref"
    lenv[tree[1]]
  # if文
  # minruby("if 0 == 0; x = 0; else x = 1; end")
  # => ["if",
  #     ["==", ["lit", 0], ["lit", 0]],
  #     ["var_assign", "x", ["lit", 0]],
  #     ["var_assign", "x", ["lit", 1]]]
  # tree[1]の条件式を評価，trueならtree[2]を，falseならtree[3]を計算
  # ifを使えばいいのでは
  # 余談だが，(本来のRubyは微妙に違うが，)case文はif文の入れ子(糖衣構文)ので，これでcase文も動く
  when "if"
    if evaluate(tree[1], genv, lenv)
      evaluate(tree[2], genv, lenv)
    else
      evaluate(tree[3], genv, lenv)
    end
  # while文
  # minruby_parse("i = 0; while i < 10; i = i + 1; end")
  # => ["stmts",
  #     ["var_assign", "i", ["lit", 0]],
  #     ["while",
  #      ["<", ["var_ref", "i"], ["lit", 10]],
  #      ["var_assign", "i", ["+", ["var_ref", "i"], ["lit", 1]]]]]
  # tree[1]の条件式を評価，tree[2]を計算
  # whileを使えばいい(ifと同じ発想)
  when "while"
    while evaluate(tree[1], genv, lenv)
      evaluate(tree[2], genv, lenv)
    end
  # begin ... end while
  # minruby_parse("i = 10; begin i = i - 1; end while i > 0")
  # => ["stmts",
  #     ["var_assign", "i", ["lit", 10]],
  #     ["while2",
  #      [">", ["var_ref", "i"], ["lit", 0]],
  #      ["var_assign", "i", ["-", ["var_ref", "i"], ["lit", 1]]]]]
  # whileとほぼ一緒
  # 処理の順番をほんの少し変えるだけ
  when "while2"
    evaluate(tree[2], genv, lenv)
    while evaluate(tree[1], genv, lenv)
      evaluate(tree[2], genv, lenv)
    end
  # 関数定義(ユーザ定義関数)
  # minruby_parse("def add(x, y) x + y; end")
  # => ["func_def", "add", ["x", "y"], ["+", ["var_ref", "x"], ["var_ref", "y"]]]
  # 組み込み関数と分けるために"user_defined"を先頭に仕込む
  # 変数同様に関数名と中身(仮引数名の配列+関数本体)を対応付けて覚えさせるためにハッシュを使用
  when "func_def"
    genv[tree[1]] = ["user_defined", tree[2], tree[3]]
  # 関数呼び出し
  # minruby_parse("p(1)") => ["func_call", "p", ["lit", 1]]
  # 引数は複数取れるので，順番に評価していく(Rubyは引数が複数のときは前から評価される)
  when "func_call"
    args = []
    i = 0
    while tree[i + 2]
      args[i] = evaluate(tree[i + 2], genv, lenv)
      i = i + 1
    end
    # 組み込まれている定義を関数名から取得
    # genv = { <<関数名>> => ["builtin" or "user_defined", <<本物のRubyの関数名>>] }
    # tree[1]に関数名が入っているので，それをハッシュのkeyとして呼び出す
    mhd = genv[tree[1]]
    # 組み込み関数に対する呼び出し
    if mhd[0] == "builtin"
      # 本物のRubyの関数に引数を渡して呼び出したい
      # 本物のRubyの関数名はmhd[1]に，引数はargsに入っている
      # minrubyパッケージに組み込まれているminruby_callを使用
      # minruby_call("add", [1, 2]) => add(1, 2)
      minruby_call(mhd[1], args)
    # ユーザ定義関数に対する呼び出し
    else
      # 関数内ではローカル変数を使用したいので，ここで定義
      new_lenv = {}
      # 仮引数それぞれに，対応する実引数を覚えさせて関数本体を評価
      # ユーザ定義関数において，mhd[1]には仮引数が，argsには実引数が入っている
      # 何かを覚えさせるということは変数
      params = mhd[1]
      i = 0
      while params[i]
        new_lenv[params[i]] = args[i]
        i = i + 1
      end
      # 最後に関数本体を評価
      evaluate(mhd[2], genv, new_lenv)
    end
  # 配列
  # 配列は作る・参照・代入の3工程必要
  # まずは配列を作る(配列構築子)
  # minruby_parse("[1, 2, 3]") => ["ary_new", ["lit", 1], ["lit", 2], ["lit", 3]]
  # 配列の実装には配列を使えば良い
  when "ary_new"
    ary = []
    i = 0
    while tree[i + 1]
      ary[i] = evaluate(tree[i + 1], genv, lenv)
      i = i + 1
    end
    ary
  # 配列参照
  # minruby_parse("ary = [1]; ary[0]")
  # => ["stmts",
  #     ["var_assign", "ary", ["ary_new", ["lit", 1]]],
  #     ["ary_ref", ["var_ref", "ary"], ["lit", 0]]]
  # 配列を表す式(ary[0]のary)を評価して，配列を表す式が表す配列を取得
  # インデックスを表す式(ary[0]の0)を評価して，インデックスを表す式が表すインデックスを取得
  # Rubyの配列参照を使う
  when "ary_ref"
    ary = evaluate(tree[1], genv, lenv)
    idx = evaluate(tree[2], genv, lenv)
    ary[idx]
  # 配列代入
  # minruby_parse("ary = [1]; ary[0] = 5")
  # => ["stmts",
  #     ["var_assign", "ary", ["ary_new", ["lit", 1]]],
  #     ["ary_assign", ["var_ref", "ary"], ["lit", 0], ["lit", 5]]]
  # 参照とほぼ同じで，tree[3]の値を評価して代入すればいい
  when "ary_assign"
    ary = evaluate(tree[1], genv, lenv)
    idx = evaluate(tree[2], genv, lenv)
    val = evaluate(tree[3], genv, lenv)
    ary[idx] = val
  # ハッシュ
  # ハッシュも配列同様に作る・参照・代入の3工程
  # しかし，実は参照と代入は配列と全く同じものを使用している
  # つまり，ハッシュ用に新しく実装する必要はない
  # 作るべきはハッシュ構築子
  # minruby_parse("{ 1 => 10, 2 => 20 }")
  # => ["hash_new", ["lit", 1], ["lit", 10], ["lit", 2], ["lit", 20]]
  # ハッシュの実装もハッシュを使えばいい
  # tree[1]以降はkeyとvalueが順番に並んでいるだけなのでそこを取り出せばいい
  when "hash_new"
    hsh = {}
    i = 0
    while tree[i + 1]
      key = evaluate(tree[i + 1], genv, lenv)
      val = evaluate(tree[i + 2], genv, lenv)
      hsh[key] = val
      i = i + 2
    end
    hsh
  end
end

# プログラムのファイルを取り込む
str = minruby_load()
# パースして抽象構文木にする
tree = minruby_parse(str)
# 組み込み関数はここで事前に定義しておく
# 今回はこのinterpreterをこのinterpreterを使って動かせるように実装
genv = {
  "p" => ["builtin", "p"],
  "require" => ["builtin", "require"],
  "minruby_parse" => ["builtin", "minruby_parse"],
  "minruby_load" => ["builtin", "minruby_load"],
  "minruby_call" => ["builtin", "minruby_call"]
}
# 変数用のハッシュ
lenv = {}
evaluate(tree, genv, lenv)
