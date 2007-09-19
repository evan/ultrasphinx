
require "#{File.dirname(__FILE__)}/../test_helper.rb"

describe "a complex configuration" do
  def setup
    @conf = {'fields' => [
          {'field'=> 'name', 'function_sql' => "replace(?,E'\\'','')"}
        ],
        'include' => [
        {'class_name' => 'Artist', 'field' => 'name', 'as' => 'artist_name', 'association_sql'=>'MOO MO'},
        {'class_name' => 'Album', 'field' => 'name', 'as'=>'album_name','association_sql' => 'LEFT OUTER JOIN public.albumjoin ON public.albumjoin.track = public.track.id LEFT OUTER JOIN public.album ON public.albumjoin.album=public.album.id LEFT OUTER JOIN public.artist ON public.artist.id = public.track.artist', 'as'=>'album_name'}
        ]
      }
      
  end
  
  it "should build the unified index" do
    sources = ["restaurants", "blog_posts", "recipes", "topics", "stories", "ingredients"]
    result = ["\n# Index configuration\n\n", "index complete\n{", "source = restaurants\nsource = blog_posts\nsource = recipes\nsource = topics\nsource = stories\nsource = ingredients", "  charset_type = utf-8\n  charset_table = 0..9, A..Z->a..z, -, _, ., &, a..z,\n  min_word_len = 1\n  stopwords = \n  path = /opt/local/var/db/sphinx//sphinx_index_complete\n  docinfo = extern\n  morphology = stem_en", "}\n\n"]
    Ultrasphinx::Configure.send(:build_index, sources).should.equal(result)  
  end    
  
end
