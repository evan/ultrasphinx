
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
  
  it "should not drop fields" do
    
  end    
end
