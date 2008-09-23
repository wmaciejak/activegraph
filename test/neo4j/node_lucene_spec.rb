require 'neo4j'
require 'neo4j/spec_helper'


  
  
describe "Neo4j & Lucene Transaction Synchronization:" do
  before(:all) do
    start
    class TestNode 
      include Neo4j::Node
      properties :name, :age
      index :name
      index :age
    end
  end
  after(:all) do
    stop
  end  
    
  it "should not update the index if the transaction rollsback" do
    # given
    n1 = nil
    Neo4j::Transaction.run do |t|
      n1 = TestNode.new
      n1.name = 'hello'
        
      # when
      t.failure  
    end
      
    # then
    n1.should_not be_nil
    TestNode.find(:name => 'hello').should_not include(n1)
  end
    
  it "should reindex when a property has been changed" do
    # given
    n1 = TestNode.new
    n1.name = 'hi'
    TestNode.find(:name => 'hi').should include(n1)
      
      
    # when
    n1.name = "oj"
      
    # then
    TestNode.find(:name => 'hi').should_not include(n1)
    TestNode.find(:name => 'oj').should include(n1)      
  end
    
  it "should remove the index when a node has been deleted" do
    # given
    n1 = TestNode.new
    n1.name = 'remove'

    # make sure we can find it
    TestNode.find(:name => 'remove').should include(n1)            
      
    # when
    n1.delete
      
    # then
    TestNode.find(:name => 'remove').should_not include(n1)
  end
end

describe "A node with no lucene index" do
  before(:all) do
    start
    class TestNodeWithNoIndex
      include Neo4j::Node
    end
    
  end
  
  after(:all) do
    stop
  end  

  it "should return no nodes in a query" do
    found = TestNodeWithNoIndex.find(:age => 0)
    
    found.should == []
  end
end
  
describe "Find Nodes using Lucene" do
  before(:all) do
    start
    class TestNode 
      include Neo4j::Node
      properties :name, :age, :male, :height
      index :name
      index :age
      index :male
      index :height
    end
    @foos = []
    5.times {|n|
      node = TestNode.new
      node.name = "foo#{n}"
      node.age = n # "#{n}"
      node.male = (n == 0)
      node.height = n * 0.1
      @foos << node
    }
    @bars = []
    5.times {|n|
      node = TestNode.new
      node.name = "bar#{n}"
      node.age = n # "#{n}"
      node.male = (n == 0) 
      node.height = n * 0.1        
      @bars << node
    }
  end
    
  after(:all) do
    stop
  end  
  
  it "should find one node" do
    found = TestNode.find(:name => 'foo2')
    found[0].name.should == 'foo2'
    found.should include(@foos[2])
    found.size.should == 1
  end

  it "should find two nodes" do
    found = TestNode.find(:age => 0)
    found.should include(@foos[0])
    found.should include(@bars[0])      
    found.size.should == 2
  end

  it "should find using two fields" do
    found = TestNode.find(:age => 0, :name => 'foo0')
    found.should include(@foos[0])
    found.size.should == 1
  end
    
  it "should find using a boolean property query" do
    found = TestNode.find(:male => true)
    found.should include(@foos[0], @bars[0])
    found.size.should == 2
  end
    
  it "should find using a float property query" do
    found = TestNode.find(:height => 0.2)
    found.should include(@foos[2], @bars[2])
    found.size.should == 2
  end
    
  
  it "should find using a DSL query" do
    found = TestNode.find{(age == 0) && (name == 'foo0')}
    found.should include(@foos[0])
    found.size.should == 1
  end
end

describe Neo4j::Node, " index on relationship" do

  before(:all) do
    # given
    class Order
      include Neo4j::Node
      properties :cost
    end
    class Customer
      include Neo4j::Node
      has :zero_or_more, Order   
      properties :name      
    end
    
    Order.index_rel(Customer, 'orders', 'Customer.name'){name}
  end
  
  before(:each) do  # we need to remove the index before each spec
    start
  end
  
  after(:each) do
    stop
  end  

  
  it "should not index nodes that are not part of the relationship" do
    # when
    c = Customer.new
    o = Order.new
    c.name = "kalle"
    o.cost = "123"
    
    # then
    orders = Order.find('Customer.name' => 'kalle')
    orders.size.should == 0
  end

  it "should index existing relationships" do
    # when
    c = Customer.new
    o = Order.new
    c.orders << o
    c.name = "kalle"
    o.cost = "123"
    
    # then
    orders = Order.find('Customer.name' => 'kalle')
    orders.size.should == 1
    orders[0].should == c
  end

  it "should index new relationships" do
    # when
    c = Customer.new
    o = Order.new
    c.name = "kalle"
    o.cost = "123"
    c.orders << o      
    
    # then
    orders = Order.find('Customer.name' => 'kalle')
    orders.size.should == 1
    orders[0].should == c
  end

  it "should remove the index when the relationship is deleted" do
    # when
    c = Customer.new
    o = Order.new
    c.name = "kalle"
    o.cost = "123"
    c.orders << o      
    orders = Order.find('Customer.name' => 'kalle')
    orders.size.should == 1
    
    # when
    c.relations.outgoing(:orders)[o].delete
    c.relations.outgoing(:orders).to_a.size.should == 0
    #_neo_rel_id
    r = Customer.lucene_index.find(:_neo_rel_class => Order.to_s.to_sym)
    r.size.should == 1
    r = Customer.find(:_neo_rel_id => 2)
    r.size.should == 1
    orders = Order.find('Customer.name' => 'kalle')
    puts "NEO NODEID FOUND #{orders[0]}, #{orders[0].neo_node_id}"
    orders.size.should == 0
  end
  
  it "should reindex the relationship when the node changes" do
    # given
    c = Customer.new
    o = Order.new
    c.name = "kalle"
    o.cost = "123"
    c.orders << o
    
    # when
    c.name = 'andreas'
    
    # then
    orders = Order.find('Customer.name' => 'kalle')
    orders.size.should == 0
    
    orders = Order.find('Customer.name' => 'andreas')
    orders.size.should == 1
    orders[0].should == c
  end
end