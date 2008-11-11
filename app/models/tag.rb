class Tag < ActiveRecord::Base

  TYPES = ['Rating', 'Warning', 'Category', 'Media', 'Fandom', 'Pairing', 'Character', 'Genre', 'Freeform']

  has_many :taggings
  has_many :works, :through => :taggings, :source => :taggable, :source_type => 'Work'
  has_many :bookmarks, :through => :taggings, :source => :taggable, :source_type => 'Bookmark'
  has_many :tags, :through => :taggings, :source => :taggable, :source_type => 'Tag'

  validates_presence_of :name
  validates_uniqueness_of :name, :scope => [:type]
  validates_length_of :name, :maximum => ArchiveConfig.TAG_MAX, 
                             :message => "is too long -- try using less than #{ArchiveConfig.TAG_MAX} characters or using commas to separate your tags.".t
  validates_format_of :name, 
                      :with => /\A[-a-zA-Z0-9 \/?.!''"":;\|\]\[}{=~!@#\$%^&()_+]+\z/, 
                      :message => "can only be made up of letters, numbers, spaces and basic punctuation, but not commas, asterisks or angle brackets.".t
  
  def before_validation
    self.name = name.strip.squeeze(" ") if self.name
  end

  named_scope :by_fandom, lambda { |*args| {:conditions => ["fandom_id IN (?)", args.flatten.map(&:id)] }}

  named_scope :valid, {:conditions => {:banned => false}}
  named_scope :banned, {:conditions => {:banned => true}}
  named_scope :canonical, {:conditions => {:canonical => true}}
  named_scope :by_popularity, {:order => 'taggings_count DESC'}
  named_scope :ordered_by_name, {:order => 'name ASC'}
  named_scope :unwrangled, {:conditions => {:banned => false, :canonical => false, :canonical_id => nil}}  
  named_scope :by_category, lambda { |*args| {:conditions => ["type IN (?)", args.flatten] }}  
  
  
  named_scope :on_works, lambda {|tagged_works|
    {
      :select => "DISTINCT tags.*",
      :joins => "INNER JOIN taggings on tags.id = taggings.tag_id
                  INNER JOIN works ON (works.id = taggings.taggable_id AND taggings.taggable_type = 'Work')",
      :conditions => ['works.id in (?)', tagged_works.collect(&:id)]
    }
  }
  
  def self.setup_canonical(name)
    tag = self.find_or_create_by_name(name)
    tag.update_attribute(:canonical, true)
    tag
  end
  
  def unwrangled?
    return false if (self.banned || self.canonical || self.canonical_id)
    return true
  end

  # sort tags by name
  def <=>(another_tag)
    name.downcase <=> another_tag.name.downcase
  end
  
  def synonyms
    Tag.find_all_by_canonical_id(self.id)
  end

  def synonym
    Tag.find(self.canonical_id) if self.canonical_id
  end
  
  def synonym= (tag)
    return false unless tag.canonical?
    self.update_attribute(:canonical_id, tag.id) 
    self.reassign_to_canonical
  end

  # reassign the tags's works and children to its canonical synonym
  def reassign_to_canonical
    return false unless self.synonym
    for work in self.works
      work.tags << self.synonym
      work.remove_tag(self)
    end
  end

  def update_fandom
    return if self.fandom
    fandom = self.works.first.fandoms.first rescue nil
    self.update_attribute(:fandom_id, fandom.id) if fandom
  end

  def fandom
    Fandom.find(self.fandom_id) if fandom_id
  end

end
