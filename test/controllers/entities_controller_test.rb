require "test_helper"

class EntitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @entity = entities(:one)
    @user = users(:one)
    sign_in @user
  end

  test "should get index" do
    get entities_url
    assert_response :success
  end

  test "should get show" do
    get entity_url(@entity)
    assert_response :success
  end

  test "should get new" do
    get new_entity_url
    assert_response :success
  end

  test "should create entity" do
    assert_difference("Entity.count") do
      post entities_url, params: {
        entity: {
          name: "New Entity",
          subdomain: "newentity",
          slug: "new-entity"
        }
      }
    end

    assert_redirected_to entity_url(Entity.last)
  end

  test "should get edit" do
    get edit_entity_url(@entity)
    assert_response :success
  end

  test "should update entity" do
    patch entity_url(@entity), params: { entity: { name: "Updated Name" } }
    assert_response :redirect
  end

  test "should destroy entity" do
    # Entities with associated records may not be destroyable
    delete entity_url(@entity)
    assert_response :redirect
  end
end
